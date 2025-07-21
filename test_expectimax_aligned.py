#!/usr/bin/env python
"""Test alignment between Python and OCaml expectimax implementations."""

import subprocess
from game import Game2048
from expectimax_python import max_value, expect_value, get_best_move

def test_basic_expectimax():
    """Test basic expectimax operations."""
    Game2048._init_tables()
    
    # Simple evaluation function - just count empty cells
    def simple_eval(board):
        empty_count = sum(1 for i in range(16) if ((board >> (4*i)) & 0xF) == 0)
        return float(empty_count)
    
    test_boards = [
        0x0000000000001234,  # Simple board
        0x1234567890ABCDEF,  # Complex board
        0x0000000000000000,  # Empty board
    ]
    
    print("Testing Python Expectimax Implementation")
    print("=" * 50)
    
    for board in test_boards:
        print(f"\nBoard: {board:016x}")
        
        # Test max_value at different depths
        for depth in [0, 1, 2]:
            value = max_value(board, simple_eval, depth)
            print(f"  max_value(depth={depth}): {value:.2f}")
        
        # Test best move
        move, score = get_best_move(board, simple_eval, 2)
        print(f"  best_move(depth=2): {move} (score: {score:.2f})")

def test_deterministic_game():
    """Test a deterministic game sequence."""
    Game2048._init_tables()
    
    print("\n\nTesting Deterministic Game Sequence")
    print("=" * 50)
    
    # Use a more sophisticated evaluation
    def eval_func(board):
        empty_count = sum(1 for i in range(16) if ((board >> (4*i)) & 0xF) == 0)
        max_tile = 0
        for i in range(16):
            tile = (board >> (4*i)) & 0xF
            if tile > max_tile:
                max_tile = tile
        return float(empty_count) + float(max_tile) * 10.0
    
    # Start with a specific board
    board = 0x0000000000001122  # [2,2,1,1] in bottom row
    print(f"Initial board: {board:016x}")
    
    # Make a few moves
    for i in range(3):
        move, score = get_best_move(board, eval_func, 2)
        if move is None:
            print("No valid moves!")
            break
            
        print(f"\nMove {i+1}: {move} (expected score: {score:.2f})")
        
        # Execute the move
        if move == 'up':
            board, move_score, _ = Game2048.move_up(board)
        elif move == 'down':
            board, move_score, _ = Game2048.move_down(board)
        elif move == 'left':
            board, move_score, _ = Game2048.move_left(board)
        elif move == 'right':
            board, move_score, _ = Game2048.move_right(board)
        
        print(f"After move: {board:016x} (actual score: {move_score})")

if __name__ == "__main__":
    test_basic_expectimax()
    test_deterministic_game()