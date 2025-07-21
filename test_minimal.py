#!/usr/bin/env python
"""Minimal test matching OCaml version."""

from test_deterministic import load_random_tape, add_tile_deterministic
from game import Game2048

# Initialize
Game2048._init_tables()

# Load tape
events, _ = load_random_tape("test_controlled.txt")
tape_data = (events, 0)

# Initial empty board
board = 0

# Add two initial tiles
board, tape_data = add_tile_deterministic(board, tape_data)
print(f"After tile 1: {board:016x}")

board, tape_data = add_tile_deterministic(board, tape_data)
print(f"After tile 2: {board:016x}")

# Make a move
board, score, _ = Game2048.move_left(board)
print(f"After left move: {board:016x}")

# Add another tile
board, tape_data = add_tile_deterministic(board, tape_data)
print(f"After tile 3: {board:016x}")

print(f"Tape position used: {tape_data[1]}")