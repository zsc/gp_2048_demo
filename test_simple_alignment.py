#!/usr/bin/env python
"""Simple alignment test focusing on basic operations."""

import subprocess
from game import Game2048

def test_basic_moves():
    """Test that basic moves produce identical results."""
    print("=== Testing Basic Move Alignment ===\n")
    
    Game2048._init_tables()
    
    # Test cases
    test_boards = [
        (0x0000000000001021, "Simple slide"),
        (0x0000000000001011, "Simple merge"),
        (0x1234000000000000, "Top row"),
        (0x0000000000004321, "Bottom row"),
        (0x1111111111111111, "All same"),
        (0x1234567890ABCDEF, "Complex board"),
    ]
    
    for board, desc in test_boards:
        print(f"\nTest: {desc}")
        print(f"Board: {board:016x}")
        
        # Test all moves
        left, score_left, _ = Game2048.move_left(board)
        right, score_right, _ = Game2048.move_right(board)
        up, score_up, _ = Game2048.move_up(board)
        down, score_down, _ = Game2048.move_down(board)
        
        print(f"Left:  {left:016x} (score: {score_left})")
        print(f"Right: {right:016x} (score: {score_right})")
        print(f"Up:    {up:016x} (score: {score_up})")
        print(f"Down:  {down:016x} (score: {score_down})")

def run_ocaml_moves(board_hex):
    """Run OCaml to test the same board."""
    ocaml_code = f'''
open Gp_2048_lib.Game

let () =
  let board = Int64.of_string "0x{board_hex:016x}" in
  let left = move_left board in
  let right = move_right board in
  let up = move_up board in
  let down = move_down board in
  Printf.printf "Board: %016Lx\\n" board;
  Printf.printf "Left:  %016Lx\\n" left;
  Printf.printf "Right: %016Lx\\n" right;
  Printf.printf "Up:    %016Lx\\n" up;
  Printf.printf "Down:  %016Lx\\n" down
'''
    
    # Write temporary OCaml file
    with open('temp_test.ml', 'w') as f:
        f.write(ocaml_code)
    
    # Compile and run
    subprocess.run(['dune', 'exec', 'ocaml', 'temp_test.ml'], capture_output=True)
    
def test_deterministic_game():
    """Test a simple deterministic game sequence."""
    print("\n\n=== Testing Deterministic Game Sequence ===\n")
    
    Game2048._init_tables()
    
    # Start with specific board
    board = 0x0000000000001011  # [1,1,0,1] = [2,2,0,2]
    print(f"Initial board: {board:016x}")
    
    # Sequence of moves
    moves = ['left', 'up', 'right', 'down']
    
    for move in moves:
        if move == 'left':
            board, score, _ = Game2048.move_left(board)
        elif move == 'right':
            board, score, _ = Game2048.move_right(board)
        elif move == 'up':
            board, score, _ = Game2048.move_up(board)
        elif move == 'down':
            board, score, _ = Game2048.move_down(board)
        
        print(f"After {move}: {board:016x} (score: {score})")
        
        # Add a tile at position 0 with value 1 (tile 2)
        if ((board >> 0) & 0xF) == 0:
            board |= 1 << 0
            print(f"Added tile at position 0: {board:016x}")

def main():
    print("Python-OCaml Basic Alignment Test\n")
    test_basic_moves()
    test_deterministic_game()

if __name__ == "__main__":
    main()