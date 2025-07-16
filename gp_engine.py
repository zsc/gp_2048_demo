# gp_2048_demo/gp_engine.py

import random
import copy
import numpy as np
import unittest
from typing import List, Set, Tuple, Any
from multiprocessing import Pool
from torch.utils.tensorboard import SummaryWriter
from tqdm import tqdm

# Assuming game.py is in the same directory or accessible
from game import Game2048

# --- 1. Define the building blocks of the GP Tree (Nodes) ---

class GPNode:
    """Base class for all nodes in the Genetic Programming tree."""
    def __init__(self, name: str, arity: int):
        self.name = name
        self.arity = arity # Number of children/arguments

    def __repr__(self) -> str:
        return self.name

class Function(GPNode):
    """A function node that takes other nodes as children."""
    def eval(self, *args) -> float:
        raise NotImplementedError

class Terminal(GPNode):
    """A terminal node (leaf) in the tree. It has no children."""
    def __init__(self, name: str):
        super().__init__(name, arity=0)

    def eval(self, board: int) -> float:
        raise NotImplementedError

# --- 2. Implement Specific Functions and Terminals ---

# Function Set
class Add(Function):
    def __init__(self): super().__init__("ADD", 2)
    def eval(self, a, b) -> float: return a + b

class Sub(Function):
    def __init__(self): super().__init__("SUB", 2)
    def eval(self, a, b) -> float: return a - b

class Mul(Function):
    def __init__(self): super().__init__("MUL", 2)
    def eval(self, a, b) -> float: return a * b

class SafeDiv(Function):
    def __init__(self): super().__init__("DIV", 2)
    def eval(self, a, b) -> float:
        if abs(b) < 1e-6: return 1.0
        return a / b

class IfLTE(Function):
    def __init__(self): super().__init__("IFLTE", 4)
    def eval(self, a, b, c, d) -> float:
        return c if a <= b else d

# Terminal Set (Board Features)
class Constant(Terminal):
    def __init__(self, value: float = None):
        if value is None:
            value = random.uniform(-1.0, 1.0)
        super().__init__(f"C({value:.2f})")
        self.value = value

    def eval(self, board: int) -> float:
        return self.value

class NumEmptyCells(Terminal):
    def __init__(self): super().__init__("EMPTY")
    def eval(self, board: int) -> float:
        count = 0
        for i in range(16):
            if (board >> (i * 4)) & 0xF == 0:
                count += 1
        return float(count)

class MaxTileValue(Terminal):
    def __init__(self): super().__init__("MAX_TILE")
    def eval(self, board: int) -> float:
        return float(Game2048.get_max_tile(board))
        
class MonotonicityScore(Terminal):
    """
    Measures how well the tile values are ordered.
    Higher score is better (e.g., values increase towards a corner).
    """
    def __init__(self): super().__init__("MONO")
    def eval(self, board: int) -> float:
        board_arr = Game2048.get_board_array(board)
        scores = [0, 0, 0, 0] # L->R, R->L, U->D, D->U

        for i in range(4):
            # Rows
            for j in range(3):
                if board_arr[i, j] >= board_arr[i, j+1]: scores[0] += board_arr[i, j] - board_arr[i, j+1]
                if board_arr[i, j] <= board_arr[i, j+1]: scores[1] += board_arr[i, j+1] - board_arr[i, j]
            # Cols
            for j in range(3):
                if board_arr[j, i] >= board_arr[j+1, i]: scores[2] += board_arr[j, i] - board_arr[j+1, i]
                if board_arr[j, i] <= board_arr[j+1, i]: scores[3] += board_arr[j+1, i] - board_arr[j, i]

        return float(max(scores))

class SmoothnessScore(Terminal):
    """
    Measures the similarity between adjacent tiles.
    Lower score is better (penalizes large differences). We return the negative value.
    """
    def __init__(self): super().__init__("SMOOTH")
    def eval(self, board: int) -> float:
        board_arr = Game2048.get_board_array(board)
        smoothness = 0
        for i in range(4):
            for j in range(4):
                if board_arr[i, j] == 0: continue
                # Right neighbor
                if j < 3 and board_arr[i, j+1] != 0:
                    smoothness -= abs(np.log2(board_arr[i, j]) - np.log2(board_arr[i, j+1]))
                # Down neighbor
                if i < 3 and board_arr[i+1, j] != 0:
                    smoothness -= abs(np.log2(board_arr[i, j]) - np.log2(board_arr[i+1, j]))
        return smoothness

# --- 3. Define the Program (Individual) ---

class Program:
    """Represents a single GP individual (an expression tree)."""
    def __init__(self, nodes: List[GPNode]):
        self.nodes = nodes  # Stored in prefix notation
        self.fitness = 0.0
        self.game_score = 0
        self.max_tile = 0

    def __len__(self) -> int:
        return len(self.nodes)

    def __str__(self) -> str:
        s, _ = self._str_helper(0)
        return s

    def _str_helper(self, index: int) -> Tuple[str, int]:
        node = self.nodes[index]
        if node.arity == 0:
            return str(node), index + 1
        
        child_strs = []
        current_index = index + 1
        for _ in range(node.arity):
            child_str, next_index = self._str_helper(current_index)
            child_strs.append(child_str)
            current_index = next_index
        
        return f"{node.name}({', '.join(child_strs)})", current_index

    def eval(self, board: int) -> float:
        """Evaluate the program tree for a given board state."""
        val, _ = self._eval_helper(0, board)
        return val

    def _eval_helper(self, index: int, board: int) -> Tuple[float, int]:
        node = self.nodes[index]
        if isinstance(node, Terminal):
            return node.eval(board), index + 1
        
        child_vals = []
        current_index = index + 1
        for _ in range(node.arity):
            child_val, next_index = self._eval_helper(current_index, board)
            child_vals.append(child_val)
            current_index = next_index

        return node.eval(*child_vals), current_index

# --- 4. The Main GP Engine ---

class GPEngine:
    """Orchestrates the genetic programming evolution process."""
    def __init__(self,
                 population_size: int = 100,
                 generations: int = 50,
                 crossover_rate: float = 0.8,
                 mutation_rate: float = 0.15,
                 tournament_size: int = 5,
                 max_init_depth: int = 4,
                 max_depth: int = 8,
                 elitism_size: int = 1,
                 games_per_individual: int = 3,
                 log_dir: str = 'runs/gp_2048_demo'):
        
        self.population_size = population_size
        self.generations = generations
        self.crossover_rate = crossover_rate
        self.mutation_rate = mutation_rate
        self.tournament_size = tournament_size
        self.max_init_depth = max_init_depth
        self.max_depth = max_depth
        self.elitism_size = elitism_size
        self.games_per_individual = games_per_individual

        self.functions: List[Function] = [Add(), Sub(), Mul(), SafeDiv(), IfLTE()]
        self.terminals: List[Terminal] = [NumEmptyCells(), MaxTileValue(), MonotonicityScore(), SmoothnessScore()]
        
        self.population: List[Program] = []
        self.writer = SummaryWriter(log_dir)
        self.pool = Pool() # For parallel fitness evaluation

    def _create_random_program(self, max_depth: int) -> Program:
        """Creates a single random program using the 'grow' method."""
        nodes = self._grow(max_depth)
        return Program(nodes)

    def _grow(self, max_depth: int, current_depth: int = 0) -> List[GPNode]:
        """Recursively builds a list of nodes in prefix notation."""
        if current_depth >= max_depth:
            # Force a terminal at max depth
            node = random.choice(self.terminals + [Constant()])
        else:
            # Choose from functions or terminals
            if random.random() < 0.7: # Favor functions to build a tree
                node = copy.deepcopy(random.choice(self.functions))
            else:
                node = copy.deepcopy(random.choice(self.terminals + [Constant()]))

        nodes = [node]
        if isinstance(node, Function):
            for _ in range(node.arity):
                nodes.extend(self._grow(max_depth, current_depth + 1))
        return nodes

    def _initialize_population(self):
        """Creates the initial population of random programs."""
        self.population = [self._create_random_program(self.max_init_depth) for _ in range(self.population_size)]

    def _evaluate_fitness(self, program: Program) -> Program:
        """
        Plays games to evaluate a program's fitness.
        The strategy is to pick the move that results in the board with the highest score from the program's eval function.
        """
        total_score = 0
        total_max_tile = 0
        total_moves = 0

        for _ in range(self.games_per_individual):
            board = Game2048.reset_board()
            game_score = 0
            moves = 0
            
            while not Game2048.is_game_over(board):
                move_fns = [Game2048.move_up, Game2048.move_down, Game2048.move_left, Game2048.move_right]
                best_move = -1
                best_eval_score = -float('inf')

                possible_moves = []
                for i, move_fn in enumerate(move_fns):
                    next_board, _, moved = move_fn(board)
                    if moved:
                        possible_moves.append((i, next_board))
                
                if not possible_moves:
                    break # No valid moves, game over
                
                for i, next_board in possible_moves:
                    eval_score = program.eval(next_board)
                    if eval_score > best_eval_score:
                        best_eval_score = eval_score
                        best_move = i
                
                if best_move != -1:
                    new_board, score_gain, _ = move_fns[best_move](board)
                    board = Game2048.add_random_tile(new_board)
                    game_score += score_gain
                    moves += 1
                else: # Should not happen if possible_moves is not empty
                    break

            total_score += game_score
            total_max_tile += Game2048.get_max_tile(board)
            total_moves += moves

        avg_score = total_score / self.games_per_individual
        avg_max_tile = total_max_tile / self.games_per_individual
        
        # Fitness is a combination of score and max tile
        program.fitness = avg_score + (avg_max_tile ** 2)
        program.game_score = avg_score
        program.max_tile = avg_max_tile
        return program

    def _tournament_selection(self) -> Program:
        """Selects an individual using tournament selection."""
        tournament = random.sample(self.population, self.tournament_size)
        return max(tournament, key=lambda p: p.fitness)
    
    def _find_subtree_end(self, nodes: List[GPNode], start_index: int) -> int:
        """Finds the end index of a subtree starting at start_index."""
        node = nodes[start_index]
        if node.arity == 0:
            return start_index + 1
        
        current_index = start_index + 1
        for _ in range(node.arity):
            current_index = self._find_subtree_end(nodes, current_index)
        return current_index

    def _crossover(self, p1: Program, p2: Program) -> Tuple[Program, Program]:
        """Performs subtree crossover between two parent programs."""
        c1_nodes, c2_nodes = list(p1.nodes), list(p2.nodes)
        
        # Select crossover point in parent 1
        pt1 = random.randint(1, len(c1_nodes) - 1)
        end1 = self._find_subtree_end(c1_nodes, pt1)
        subtree1 = c1_nodes[pt1:end1]

        # Select crossover point in parent 2
        pt2 = random.randint(1, len(c2_nodes) - 1)
        end2 = self._find_subtree_end(c2_nodes, pt2)
        subtree2 = c2_nodes[pt2:end2]

        # Swap subtrees
        new_c1_nodes = c1_nodes[:pt1] + subtree2 + c1_nodes[end1:]
        new_c2_nodes = c2_nodes[:pt2] + subtree1 + c2_nodes[end2:]
        
        # Check depth constraints
        c1 = Program(new_c1_nodes)
        c2 = Program(new_c2_nodes)
        
        # A simple way to check depth is to count parenthesis in string form
        if str(c1).count('(') > self.max_depth or str(c2).count('(') > self.max_depth:
            return p1, p2 # Crossover failed, return originals

        return c1, c2

    def _mutate(self, program: Program) -> Program:
        """Performs subtree mutation on a program."""
        nodes = list(program.nodes)
        
        pt = random.randint(0, len(nodes) - 1)
        end = self._find_subtree_end(nodes, pt)
        
        # Create a new random subtree
        current_depth = str(Program(nodes[:pt])).count('(')
        new_subtree = self._grow(max_depth=self.max_depth - current_depth)
        
        mutated_nodes = nodes[:pt] + new_subtree + nodes[end:]
        
        mutated_program = Program(mutated_nodes)
        if str(mutated_program).count('(') > self.max_depth:
            return program # Mutation failed, return original

        return mutated_program

    def run(self):
        """The main evolutionary loop."""
        print("Initializing population...")
        self._initialize_population()

        for gen in range(self.generations):
            print(f"\n--- Generation {gen+1}/{self.generations} ---")
            
            # Evaluate fitness in parallel
            print("Evaluating fitness...")
            results = list(tqdm(self.pool.imap(self._evaluate_fitness, self.population), total=self.population_size))
            self.population = results

            # Sort by fitness (descending)
            self.population.sort(key=lambda p: p.fitness, reverse=True)

            best_program = self.population[0]
            avg_fitness = sum(p.fitness for p in self.population) / self.population_size
            avg_game_score = sum(p.game_score for p in self.population) / self.population_size
            avg_max_tile = sum(p.max_tile for p in self.population) / self.population_size
            
            # Log to console and TensorBoard
            print(f"Best Fitness: {best_program.fitness:.2f} | "
                  f"Best Game Score: {best_program.game_score:.0f} | "
                  f"Best Max Tile: {best_program.max_tile:.0f}")
            print(f"Avg Fitness: {avg_fitness:.2f} | "
                  f"Avg Game Score: {avg_game_score:.0f} | "
                  f"Avg Max Tile: {avg_max_tile:.0f}")

            self.writer.add_scalar('Fitness/Best', best_program.fitness, gen)
            self.writer.add_scalar('Fitness/Average', avg_fitness, gen)
            self.writer.add_scalar('Game/Best_Score', best_program.game_score, gen)
            self.writer.add_scalar('Game/Average_Score', avg_game_score, gen)
            self.writer.add_scalar('Game/Best_Max_Tile', best_program.max_tile, gen)
            self.writer.add_scalar('Game/Average_Max_Tile', avg_max_tile, gen)
            self.writer.add_scalar('Program/Avg_Size', sum(len(p) for p in self.population) / self.population_size, gen)

            # Create the next generation
            next_generation = []

            # Elitism: carry over the best individuals
            if self.elitism_size > 0:
                next_generation.extend(self.population[:self.elitism_size])

            # Generate offspring
            while len(next_generation) < self.population_size:
                p1 = self._tournament_selection()
                if random.random() < self.crossover_rate:
                    p2 = self._tournament_selection()
                    c1, c2 = self._crossover(p1, p2)
                else:
                    c1, c2 = p1, None

                if random.random() < self.mutation_rate:
                    c1 = self._mutate(c1)
                
                next_generation.append(c1)
                if c2 and len(next_generation) < self.population_size:
                    if random.random() < self.mutation_rate:
                        c2 = self._mutate(c2)
                    next_generation.append(c2)

            self.population = next_generation
        
        self.pool.close()
        self.pool.join()
        self.writer.close()
        print("\nEvolution finished.")
        return self.population[0] # Return the best program found


# --- 5. Unit Tests ---

class TestGPEngine(unittest.TestCase):
    def setUp(self):
        # A small engine for testing purposes
        self.engine = GPEngine(population_size=10, generations=2, max_init_depth=3)
        Game2048._init_tables() # Ensure game tables are ready

    def test_node_evaluation(self):
        # Test ADD(Constant(5), MUL(Constant(2), Constant(3))) -> 5 + (2*3) = 11
        add_node = Add()
        mul_node = Mul()
        c5 = Constant(5)
        c2 = Constant(2)
        c3 = Constant(3)

        self.assertEqual(add_node.eval(c5.eval(0), mul_node.eval(c2.eval(0), c3.eval(0))), 11)
        # Test SafeDiv
        div_node = SafeDiv()
        self.assertEqual(div_node.eval(10, 2), 5)
        self.assertEqual(div_node.eval(10, 0), 1) # Safe division

    def test_program_evaluation(self):
        # Program: ADD(EMPTY, MAX_TILE)
        nodes = [Add(), NumEmptyCells(), MaxTileValue()]
        program = Program(nodes)
        
        # Board: [2, 4, 0, 0] ... rest 0s. 14 empty, max tile 4.
        board = (1 << 0) | (2 << 4) 
        result = program.eval(board)
        self.assertAlmostEqual(result, 14.0 + 4.0)

        # Program: IFLTE(C(10), C(15), C(1), C(0)) -> should be 1
        nodes = [IfLTE(), Constant(10), Constant(15), Constant(1), Constant(0)]
        program = Program(nodes)
        self.assertAlmostEqual(program.eval(0), 1.0)
        
    def test_program_str_representation(self):
        nodes = [Add(), NumEmptyCells(), MaxTileValue()]
        program = Program(nodes)
        self.assertEqual(str(program), "ADD(EMPTY, MAX_TILE)")

        nodes = [IfLTE(), Constant(10), Mul(), Constant(2), Constant(3), Constant(1), Constant(0)]
        program = Program(nodes)
        self.assertEqual(str(program), "IFLTE(C(10.00), MUL(C(2.00), C(3.00)), C(1.00), C(0.00))")

    def test_find_subtree_end(self):
        # Tree: IFLTE(C(10), MUL(C(2), C(3)), C(1), C(0))
        nodes = [IfLTE(), Constant(10), Mul(), Constant(2), Constant(3), Constant(1), Constant(0)]
        
        # Subtree at index 1 is C(10), should end at 2
        self.assertEqual(self.engine._find_subtree_end(nodes, 1), 2)
        # Subtree at index 2 is MUL(C(2), C(3)), should end at 5
        self.assertEqual(self.engine._find_subtree_end(nodes, 2), 5)
        # Subtree at index 0 is the whole tree, should end at 7
        self.assertEqual(self.engine._find_subtree_end(nodes, 0), 7)

    def test_crossover(self):
        p1 = Program([Add(), NumEmptyCells(), MaxTileValue()]) # ADD(EMPTY, MAX_TILE)
        p2 = Program([Sub(), MonotonicityScore(), SmoothnessScore()]) # SUB(MONO, SMOOTH)
        
        # Manually swap the second child of p1 with the first child of p2
        # Mock random to be predictable
        random.randint = lambda a, b: 2 if b > 1 else 1 # Choose 2nd child of p1, 1st of p2
        
        c1, c2 = self.engine._crossover(p1, p2)
        
        # Expected c1: ADD(EMPTY, MONO) -> [Add, NumEmptyCells, MonotonicityScore]
        self.assertEqual(len(c1.nodes), 3)
        self.assertIsInstance(c1.nodes[0], Add)
        self.assertIsInstance(c1.nodes[1], NumEmptyCells)
        self.assertIsInstance(c1.nodes[2], MonotonicityScore)
        
        # Expected c2: SUB(MAX_TILE, SMOOTH) -> [Sub, MaxTileValue, SmoothnessScore]
        self.assertEqual(len(c2.nodes), 3)
        self.assertIsInstance(c2.nodes[0], Sub)
        self.assertIsInstance(c2.nodes[1], MaxTileValue)
        self.assertIsInstance(c2.nodes[2], SmoothnessScore)

    def test_mutation(self):
        p = Program([Add(), NumEmptyCells(), MaxTileValue()])
        # Mock random to mutate the MaxTileValue node
        random.randint = lambda a, b: 2 # Choose index 2
        # Mock grow to always produce a Constant
        self.engine._grow = lambda max_depth, current_depth=0: [Constant(99.0)]
        
        mutated_p = self.engine._mutate(p)
        
        self.assertEqual(len(mutated_p.nodes), 3)
        self.assertIsInstance(mutated_p.nodes[0], Add)
        self.assertIsInstance(mutated_p.nodes[1], NumEmptyCells)
        self.assertIsInstance(mutated_p.nodes[2], Constant)
        self.assertAlmostEqual(mutated_p.nodes[2].value, 99.0)

if __name__ == "__main__":
    # To run the full evolution (can be slow):
    # engine = GPEngine(population_size=50, generations=20, games_per_individual=5)
    # best_program = engine.run()
    # print("\n--- Best Program Found ---")
    # print(best_program)

    # To run unit tests:
    print("Running unit tests...")
    unittest.main()
