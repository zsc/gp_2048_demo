#!/usr/bin/env python
"""Expectimax algorithm extracted from app.py for alignment with OCaml."""

from game import Game2048

def max_value(board, program_eval, depth):
    """Player's turn: maximize the score from the next state."""
    if Game2048.is_game_over(board):
        return program_eval(board) - 1e6  # Penalize game over states
    if depth == 0:
        return program_eval(board)

    move_fns = {
        0: Game2048.move_up, 
        1: Game2048.move_down,
        2: Game2048.move_left, 
        3: Game2048.move_right
    }

    max_utility = -float('inf')
    has_moved = False
    
    for _, move_fn in move_fns.items():
        next_board, _, moved = move_fn(board)
        if moved:
            has_moved = True
            # After player moves, it's the computer's turn (chance node)
            utility = expect_value(next_board, program_eval, depth)
            max_utility = max(max_utility, utility)

    if not has_moved:
        return program_eval(board)

    return max_utility

def expect_value(board, program_eval, depth):
    """Computer's turn: calculate the expected score from all possible tile spawns."""
    empty_cells_indices = []
    for i in range(16):
        if (board >> (i * 4)) & 0xF == 0:
            empty_cells_indices.append(i)

    # After computer adds a tile, it's player's turn again, so we search 1 ply deeper.
    next_depth = depth - 1

    if not empty_cells_indices:
        return max_value(board, program_eval, next_depth)

    if next_depth < 0:
        return program_eval(board)

    num_empty = len(empty_cells_indices)
    
    # Weighted average of scores for adding '2' or '4'
    # val_2 is log2(2)=1, val_4 is log2(4)=2
    sum_score_2 = 0.0
    sum_score_4 = 0.0

    for cell_idx in empty_cells_indices:
        board_with_2 = board | (1 << (cell_idx * 4))
        sum_score_2 += max_value(board_with_2, program_eval, next_depth)

        board_with_4 = board | (2 << (cell_idx * 4))
        sum_score_4 += max_value(board_with_4, program_eval, next_depth)

    # Expected score = (0.9 * sum(scores_with_2) + 0.1 * sum(scores_with_4)) / num_empty
    return (0.9 * sum_score_2 + 0.1 * sum_score_4) / num_empty

def get_best_move(board, program_eval, search_depth):
    """Find the best move for a given board state."""
    move_fns = {
        'up': Game2048.move_up,
        'down': Game2048.move_down,
        'left': Game2048.move_left,
        'right': Game2048.move_right
    }
    
    best_move = None
    best_eval_score = -float('inf')
    
    # This is the root of the search, corresponding to a MAX node.
    for move_name, move_fn in move_fns.items():
        next_board, _, moved = move_fn(board)
        if moved:
            # The value of making a move is the expected value of the resulting state
            eval_score = expect_value(next_board, program_eval, search_depth)
            if eval_score > best_eval_score:
                best_eval_score = eval_score
                best_move = move_name
    
    return best_move, best_eval_score

def play_game(board, program_eval, search_depth, max_moves=1000):
    """Play a complete game using expectimax."""
    Game2048._init_tables()
    
    score = 0
    moves = 0
    
    while moves < max_moves and not Game2048.is_game_over(board):
        move_name, _ = get_best_move(board, program_eval, search_depth)
        
        if move_name is None:
            break
            
        # Execute the move
        if move_name == 'up':
            board, move_score, _ = Game2048.move_up(board)
        elif move_name == 'down':
            board, move_score, _ = Game2048.move_down(board)
        elif move_name == 'left':
            board, move_score, _ = Game2048.move_left(board)
        elif move_name == 'right':
            board, move_score, _ = Game2048.move_right(board)
        
        score += move_score
        board = Game2048.add_random_tile(board)
        moves += 1
    
    max_tile = Game2048.get_max_tile(board)
    return score, max_tile, moves

# Test functions
def test_expectimax():
    """Test the expectimax implementation."""
    Game2048._init_tables()
    
    # Simple evaluation function for testing
    def simple_eval(board):
        empty_count = sum(1 for i in range(16) if ((board >> (4*i)) & 0xF) == 0)
        return float(empty_count)
    
    # Test board
    board = 0x0000000000001234
    print(f"Test board: {board:016x}")
    
    # Test max_value
    value = max_value(board, simple_eval, 2)
    print(f"Max value (depth 2): {value}")
    
    # Test best move
    move, score = get_best_move(board, simple_eval, 2)
    print(f"Best move: {move} (score: {score})")
    
    # Test a simple game
    print("\nPlaying a test game...")
    initial_board = Game2048.reset_board()
    final_score, max_tile, num_moves = play_game(initial_board, simple_eval, 2, max_moves=100)
    print(f"Game ended: score={final_score}, max_tile={max_tile}, moves={num_moves}")

if __name__ == "__main__":
    test_expectimax()