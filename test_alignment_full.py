#!/usr/bin/env python
"""Comprehensive alignment test between Python and OCaml implementations."""

import subprocess
import json
import tempfile
import os
from game import Game2048

def test_basic_operations():
    """Test basic bit operations alignment."""
    print("=== Testing Basic Operations ===\n")
    
    # Test board representation
    board = 0x1234567890ABCDEF
    print(f"Test board: {board:016x}")
    
    # Test get_cell
    for i in range(16):
        value = (board >> (i * 4)) & 0xF
        print(f"Cell {i}: {value}")
    
    # Test transpose
    Game2048._init_tables()
    transposed = Game2048._transpose(board)
    print(f"\nTranspose: {transposed:016x}")
    
    # Test moves on a simple board
    simple_board = 0x0000000000001122  # Two 2s and two 4s in bottom row
    print(f"\nSimple board: {simple_board:016x}")
    
    left, score_left, _ = Game2048.move_left(simple_board)
    print(f"After left: {left:016x}, score: {score_left}")
    
    right, score_right, _ = Game2048.move_right(simple_board)
    print(f"After right: {right:016x}, score: {score_right}")

def run_ocaml_test(tape_file):
    """Run OCaml test and capture output."""
    result = subprocess.run(
        ["dune", "exec", "./test_deterministic.exe", tape_file],
        capture_output=True,
        text=True
    )
    return result.stdout, result.stderr

def compare_implementations(tape_file):
    """Compare Python and OCaml implementations."""
    print("\n=== Comparing Implementations ===\n")
    
    # Run OCaml version
    print("Running OCaml version...")
    ocaml_out, ocaml_err = run_ocaml_test(tape_file)
    if ocaml_err:
        print(f"OCaml error: {ocaml_err}")
        return
    
    # Parse OCaml output
    ocaml_lines = ocaml_out.strip().split('\n')
    ocaml_score = None
    ocaml_max_tile = None
    ocaml_events = None
    
    for line in ocaml_lines:
        if "Final score:" in line:
            ocaml_score = int(line.split(":")[1].strip())
        elif "Max tile:" in line:
            ocaml_max_tile = int(line.split(":")[1].strip())
        elif "Random events used:" in line:
            ocaml_events = int(line.split(":")[1].strip())
    
    print(f"OCaml results: score={ocaml_score}, max_tile={ocaml_max_tile}, events={ocaml_events}")
    
    # Run Python version
    print("\nRunning Python version...")
    import test_deterministic
    # Capture Python output by temporarily redirecting stdout
    import io
    import sys
    old_stdout = sys.stdout
    sys.stdout = buffer = io.StringIO()
    
    test_deterministic.test_with_tape(tape_file)
    
    python_out = buffer.getvalue()
    sys.stdout = old_stdout
    
    # Parse Python output
    python_lines = python_out.strip().split('\n')
    python_score = None
    python_max_tile = None
    python_events = None
    
    for line in python_lines:
        if "Final score:" in line:
            python_score = int(line.split(":")[1].strip())
        elif "Max tile:" in line:
            python_max_tile = int(line.split(":")[1].strip())
        elif "Random events used:" in line:
            python_events = int(line.split(":")[1].strip())
    
    print(f"Python results: score={python_score}, max_tile={python_max_tile}, events={python_events}")
    
    # Compare results
    print("\n=== Comparison ===")
    print(f"Scores match: {ocaml_score == python_score}")
    print(f"Max tiles match: {ocaml_max_tile == python_max_tile}")
    print(f"Events used match: {ocaml_events == python_events}")
    
    if ocaml_score != python_score or ocaml_max_tile != python_max_tile:
        print("\n⚠️  MISMATCH DETECTED! Implementations are not aligned.")
    else:
        print("\n✅ Implementations are aligned!")

def main():
    print("2048 Python-OCaml Alignment Test\n")
    
    # Test basic operations
    test_basic_operations()
    
    # Compare full game implementations
    compare_implementations("test_tape.txt")

if __name__ == "__main__":
    main()