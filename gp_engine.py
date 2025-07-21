# gp_engine.py

import random
import copy
import numpy as np
import time
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

# === 高级函数节点 v1.1 ===
class Min(Function):
    """返回两个值中的最小值，用于显式优化比较"""
    def __init__(self): super().__init__("MIN", 2)
    def eval(self, a, b) -> float: return min(a, b)

class Max(Function):
    """返回两个值中的最大值，用于显式优化比较"""
    def __init__(self): super().__init__("MAX", 2)  
    def eval(self, a, b) -> float: return max(a, b)

class Sigmoid(Function):
    """S型激活函数，将输入映射到(0,1)区间"""
    def __init__(self): super().__init__("SIGMOID", 1)
    def eval(self, x) -> float:
        import math
        try:
            return 1.0 / (1.0 + math.exp(-max(-500, min(500, x))))  # 防止溢出
        except:
            return 0.5  # 默认值

class WeightedAvg(Function):
    """加权平均，允许动态特征加权: (a*w + b*(1-w))，w通过sigmoid归一化"""
    def __init__(self): super().__init__("WAVG", 3)
    def eval(self, a, b, w) -> float:
        import math
        try:
            # 将权重w通过sigmoid映射到(0,1)
            weight = 1.0 / (1.0 + math.exp(-max(-500, min(500, w))))
            return a * weight + b * (1.0 - weight)
        except:
            return (a + b) / 2.0  # 默认等权重平均

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

# === 增强终端节点 v1.0 ===
class CornerPreference(Terminal):
    """
    测量高数值方块在角落的位置偏好。
    角落位置权重更高，鼓励大方块聚集在角落。
    """
    def __init__(self): super().__init__("CORNER")
    def eval(self, board: int) -> float:
        board_arr = Game2048.get_board_array(board)
        # 角落权重矩阵，角落权重最高
        weights = np.array([
            [16, 8, 4, 2],
            [8,  4, 2, 1],
            [4,  2, 1, 0.5],
            [2,  1, 0.5, 0.25]
        ])
        # 计算加权分数，高数值方块在角落得分更高
        score = 0.0
        for i in range(4):
            for j in range(4):
                if board_arr[i, j] > 0:
                    score += np.log2(board_arr[i, j]) * weights[i, j]
        return score

class MergePotential(Terminal):
    """
    计算即时合并机会数量。
    统计相邻相同方块的对数，更多合并机会意味着更好的位置。
    """
    def __init__(self): super().__init__("MERGE")
    def eval(self, board: int) -> float:
        board_arr = Game2048.get_board_array(board)
        merge_count = 0
        
        # 检查水平相邻
        for i in range(4):
            for j in range(3):
                if board_arr[i, j] > 0 and board_arr[i, j] == board_arr[i, j+1]:
                    merge_count += 1
        
        # 检查垂直相邻
        for i in range(3):
            for j in range(4):
                if board_arr[i, j] > 0 and board_arr[i, j] == board_arr[i+1, j]:
                    merge_count += 1
        
        return float(merge_count)

class EdgeAlignment(Terminal):
    """
    评估方块沿棋盘边缘的排列质量。
    边缘位置的高数值方块获得奖励。
    """
    def __init__(self): super().__init__("EDGE")
    def eval(self, board: int) -> float:
        board_arr = Game2048.get_board_array(board)
        edge_score = 0.0
        
        # 边缘位置权重
        edge_weight = 2.0
        corner_weight = 4.0
        
        for i in range(4):
            for j in range(4):
                if board_arr[i, j] > 0:
                    tile_value = np.log2(board_arr[i, j])
                    # 角落位置
                    if (i == 0 or i == 3) and (j == 0 or j == 3):
                        edge_score += tile_value * corner_weight
                    # 边缘位置
                    elif i == 0 or i == 3 or j == 0 or j == 3:
                        edge_score += tile_value * edge_weight
        
        return edge_score

# === v1.3 游戏阶段感知终端节点 ===
class GamePhase(Terminal):
    """识别游戏阶段: 早期(<512), 中期(512-2048), 后期(>2048)"""
    def __init__(self): super().__init__("PHASE")
    def eval(self, board: int) -> float:
        max_tile = Game2048.get_max_tile(board)
        if max_tile < 512: return 0.0  # 早期
        elif max_tile < 2048: return 1.0  # 中期
        else: return 2.0  # 后期

class ClusterCompactness(Terminal):
    """测量高数值方块的聚集程度，紧密聚集得分更高"""
    def __init__(self): super().__init__("CLUSTER")
    def eval(self, board: int) -> float:
        board_arr = Game2048.get_board_array(board)
        cluster_score = 0.0
        
        # 找出所有高价值方块(>=64)
        high_value_positions = []
        for i in range(4):
            for j in range(4):
                if board_arr[i, j] >= 64:
                    high_value_positions.append((i, j, board_arr[i, j]))
        
        if len(high_value_positions) < 2:
            return 0.0
        
        # 计算高价值方块之间的紧密度
        for idx1, (i1, j1, val1) in enumerate(high_value_positions):
            for idx2 in range(idx1 + 1, len(high_value_positions)):
                i2, j2, val2 = high_value_positions[idx2]
                # 曼哈顿距离
                distance = abs(i1 - i2) + abs(j1 - j2)
                # 距离越近，分数越高，同时考虑方块值
                if distance == 1:  # 相邻
                    cluster_score += (val1 + val2) / 64.0
                elif distance == 2:  # 对角或隔一格
                    cluster_score += (val1 + val2) / 128.0
        
        return cluster_score

class FutureMovePotential(Terminal):
    """评估未来潜在的合并机会，考虑相隔一格的相同方块"""
    def __init__(self): super().__init__("FUTURE")
    def eval(self, board: int) -> float:
        board_arr = Game2048.get_board_array(board)
        future_score = 0.0
        
        # 检查相隔一格的相同方块（可以通过一次移动合并）
        for i in range(4):
            for j in range(4):
                if board_arr[i, j] == 0:
                    continue
                    
                # 检查向右隔一格
                if j < 2 and board_arr[i, j] == board_arr[i, j+2]:
                    # 检查中间是否可以清空
                    if board_arr[i, j+1] == 0 or board_arr[i, j+1] < board_arr[i, j]:
                        future_score += np.log2(board_arr[i, j])
                
                # 检查向下隔一格
                if i < 2 and board_arr[i, j] == board_arr[i+2, j]:
                    # 检查中间是否可以清空
                    if board_arr[i+1, j] == 0 or board_arr[i+1, j] < board_arr[i, j]:
                        future_score += np.log2(board_arr[i, j])
        
        # 额外奖励：检查L形和T形潜在合并模式
        for i in range(3):
            for j in range(3):
                # L形模式
                if board_arr[i, j] > 0:
                    if board_arr[i, j] == board_arr[i+1, j] == board_arr[i, j+1]:
                        future_score += np.log2(board_arr[i, j]) * 1.5
                    if board_arr[i, j] == board_arr[i+1, j] == board_arr[i+1, j+1]:
                        future_score += np.log2(board_arr[i, j]) * 1.5
        
        return future_score

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

# --- Expectimax Helpers for Fitness Evaluation ---
# These are defined at the top level for multiprocessing compatibility.

def _gp_max_value(board: int, program: Program, depth: int) -> float:
    """Player's turn (MAX node)."""
    if Game2048.is_game_over(board):
        return program.eval(board) - 1e7 # Heavily penalize game over
    if depth == 0:
        return program.eval(board)

    max_utility = -float('inf')
    moved_at_all = False
    for move_fn in [Game2048.move_up, Game2048.move_down, Game2048.move_left, Game2048.move_right]:
        next_board, _, moved = move_fn(board)
        if moved:
            moved_at_all = True
            utility = _gp_expect_value(next_board, program, depth)
            if utility > max_utility:
                max_utility = utility

    if not moved_at_all:
        return program.eval(board)

    return max_utility

def _gp_expect_value(board: int, program: Program, depth: int) -> float:
    """Computer's turn (CHANCE node)."""
    empty_cells_indices = []
    for i in range(16):
        if (board >> (i * 4)) & 0xF == 0:
            empty_cells_indices.append(i)

    if not empty_cells_indices:
        return _gp_max_value(board, program, depth - 1)

    num_empty = len(empty_cells_indices)
    next_depth = depth - 1

    if next_depth < 0:
        return program.eval(board)

    total_utility = 0.0
    for cell_idx in empty_cells_indices:
        # Probability 0.9 for tile 2 (log2 value 1)
        board_with_2 = board | (1 << (cell_idx * 4))
        total_utility += 0.9 * _gp_max_value(board_with_2, program, next_depth)

        # Probability 0.1 for tile 4 (log2 value 2)
        board_with_4 = board | (2 << (cell_idx * 4))
        total_utility += 0.1 * _gp_max_value(board_with_4, program, next_depth)

    return total_utility / num_empty

# This is a top-level function to be used with multiprocessing.Pool
# to avoid pickling errors with instance methods.
def evaluate_fitness_worker(args: Tuple[Program, int, int]) -> Program:
    """
    Plays games to evaluate a program's fitness using Expectimax search.
    """
    program, games_per_individual, search_depth = args
    total_score = 0
    total_max_tile = 0
    total_moves = 0
    for _ in range(games_per_individual):
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
            
            # Use Expectimax to find the best move
            if search_depth > 0:
                for i, next_board in possible_moves:
                    # After our move, it's the computer's turn (expect node)
                    eval_score = _gp_expect_value(next_board, program, search_depth)
                    if eval_score > best_eval_score:
                        best_eval_score = eval_score
                        best_move = i
            else: # Fallback to greedy (depth 0) if search_depth is 0 or less
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

    avg_score = total_score / games_per_individual
    avg_max_tile = total_max_tile / games_per_individual
    avg_moves = total_moves / games_per_individual
    
    # === 增强适应度函数 v1.2 ===
    # 基础分数和最大方块
    base_fitness = avg_score + (avg_max_tile ** 2.5)  # 更重地加权最大方块
    
    # 里程碑奖励
    milestone_bonus = 0
    if avg_max_tile >= 512:  milestone_bonus += 1000
    if avg_max_tile >= 1024: milestone_bonus += 5000
    if avg_max_tile >= 2048: milestone_bonus += 20000
    if avg_max_tile >= 4096: milestone_bonus += 100000
    
    # 效率奖励 - 惩罚过长的游戏，鼓励高效游戏
    efficiency_bonus = 0
    if avg_moves > 0:
        score_per_move = avg_score / avg_moves
        efficiency_bonus = score_per_move * 10  # 每步得分的10倍作为效率奖励
        
        # 如果达到高方块但步数过多，给予惩罚
        if avg_max_tile >= 1024 and avg_moves > 2000:
            efficiency_bonus -= (avg_moves - 2000) * 0.5
    
    # 最终适应度
    program.fitness = base_fitness + milestone_bonus + efficiency_bonus
    program.game_score = avg_score
    program.max_tile = avg_max_tile
    return program

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
                 fitness_search_depth: int = 1,
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
        self.fitness_search_depth = fitness_search_depth

        self.functions: List[Function] = [Add(), Sub(), Mul(), SafeDiv(), IfLTE(),
                                          Min(), Max(), Sigmoid(), WeightedAvg()]
        self.terminals: List[Terminal] = [NumEmptyCells(), MaxTileValue(), MonotonicityScore(), SmoothnessScore(),
                                          CornerPreference(), MergePotential(), EdgeAlignment(),
                                          GamePhase(), ClusterCompactness(), FutureMovePotential()]
        
        self.population: List[Program] = []
        self.writer = SummaryWriter(log_dir)
        # Use 80% of available CPUs to leave some for system
        import multiprocessing
        self.num_cpus = max(1, int(multiprocessing.cpu_count() * 0.8))
        print(f"使用 {self.num_cpus}/{multiprocessing.cpu_count()} 个CPU核心进行并行计算")
        self.pool = Pool(processes=self.num_cpus)

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

        # If either parent is too small to have a non-root subtree, abort crossover.
        if len(c1_nodes) <= 1 or len(c2_nodes) <= 1:
            return p1, p2
        
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

    def _get_depth_of_node(self, nodes: List[GPNode], target_index: int) -> int:
        """Calculates the depth of a node at a specific index in a prefix list."""
        if target_index == 0:
            return 0

        depth = 0
        # A stack tracking the number of remaining children for parent nodes.
        children_counts = []

        i = 0
        while i < target_index:
            node = nodes[i]

            if children_counts:
                children_counts[-1] -= 1

            if node.arity > 0:
                depth += 1
                children_counts.append(node.arity)

            while children_counts and children_counts[-1] == 0:
                children_counts.pop()
                depth -= 1
            i += 1
        return depth

    def _mutate(self, program: Program) -> Program:
        """Performs subtree mutation on a program."""
        nodes = list(program.nodes)
        
        pt = random.randint(0, len(nodes) - 1)
        end = self._find_subtree_end(nodes, pt)
        
        # Create a new random subtree
        current_depth = self._get_depth_of_node(nodes, pt)
        new_subtree = self._grow(max_depth=self.max_depth - current_depth, current_depth=0)
        
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
            gen_start_time = time.time()
            print(f"\n--- Generation {gen+1}/{self.generations} ---")
            
            # Evaluate fitness in parallel
            eval_start_time = time.time()
            print("Evaluating fitness...")
            # We pass tuples of (program, games_per_individual, search_depth) to the worker
            eval_args = [(p, self.games_per_individual, self.fitness_search_depth) for p in self.population]
            
            # Use map instead of imap for better CPU utilization
            # Calculate optimal chunksize for load balancing
            chunksize = max(1, self.population_size // (self.num_cpus * 4))
            
            # Option 1: Use map without progress bar (better CPU usage)
            results = self.pool.map(evaluate_fitness_worker, eval_args, chunksize=chunksize)
            
            # Option 2: If progress bar is needed, use imap_unordered with larger chunks
            # results = list(tqdm(self.pool.imap_unordered(evaluate_fitness_worker, eval_args, chunksize=chunksize), 
            #                    total=self.population_size))
            
            self.population = results
            
            eval_time = time.time() - eval_start_time
            print(f"Fitness evaluation completed in {eval_time:.1f}s")

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

    def tearDown(self):
        """Clean up resources after tests."""
        self.engine.pool.close()
        self.engine.pool.join()

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
        
        # Mock random to be predictable.
        # The lambda will return 2 for `randint(1,2)` which is the range for both parents.
        random.randint = lambda a, b: 2 if b > 1 else 1
        
        c1, c2 = self.engine._crossover(p1, p2)
        
        # The mock selects index 2 for both parents. This swaps p1's MaxTileValue with p2's SmoothnessScore.
        # c1 becomes ADD(EMPTY, SMOOTH)
        # c2 becomes SUB(MONO, MAX_TILE)
        
        # Expected c1: [Add, NumEmptyCells, SmoothnessScore]
        self.assertEqual(len(c1.nodes), 3)
        self.assertIsInstance(c1.nodes[0], Add)
        self.assertIsInstance(c1.nodes[1], NumEmptyCells)
        self.assertIsInstance(c1.nodes[2], SmoothnessScore)
        
        # Expected c2: [Sub, MonotonicityScore, MaxTileValue]
        self.assertEqual(len(c2.nodes), 3)
        self.assertIsInstance(c2.nodes[0], Sub)
        self.assertIsInstance(c2.nodes[1], MonotonicityScore)
        self.assertIsInstance(c2.nodes[2], MaxTileValue)

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
