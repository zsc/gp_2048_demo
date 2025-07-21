#!/usr/bin/env python
"""Test deterministic gameplay using external random tape."""

import numpy as np
from game import Game2048

# Simple GP nodes matching OCaml implementation
class GPNode:
    ADD = 0
    SUB = 1
    MUL = 2
    SAFEDIV = 3
    IFLTE = 4
    CONSTANT = 5
    NUM_EMPTY_CELLS = 6
    MAX_TILE_VALUE = 7
    MONOTONICITY_SCORE = 8
    SMOOTHNESS_SCORE = 9

def eval_program(program, board):
    """Evaluate a GP program on a board state."""
    def safe_div(a, b):
        return 1.0 if abs(b) < 0.001 else a / b
    
    def eval_node(idx):
        if idx >= len(program):
            return 0.0, idx
        
        node = program[idx]
        
        if isinstance(node, (int, float)) and node == GPNode.ADD:
            v1, idx1 = eval_node(idx + 1)
            v2, idx2 = eval_node(idx1)
            return v1 + v2, idx2
        elif node == GPNode.MUL:
            v1, idx1 = eval_node(idx + 1)
            v2, idx2 = eval_node(idx1)
            return v1 * v2, idx2
        elif node == GPNode.NUM_EMPTY_CELLS:
            count = sum(1 for i in range(16) if ((board >> (4*i)) & 0xF) == 0)
            return float(count), idx + 1
        elif node == GPNode.MONOTONICITY_SCORE:
            # Simple monotonicity - just return negative value
            return -10.0, idx + 1
        elif node == GPNode.SMOOTHNESS_SCORE:
            # Simple smoothness - just return negative value
            return -5.0, idx + 1
        else:
            return 0.0, idx + 1
    
    result, _ = eval_node(0)
    return result

def load_random_tape(filename):
    """Load random tape from file."""
    events = []
    with open(filename, 'r') as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith('#'):
                parts = line.split()
                if len(parts) >= 2:
                    position = int(parts[0])
                    value = int(parts[1])
                    events.append((position, value))
    return events, 0  # events and current index

def get_next_event(tape_data):
    """Get next event from tape."""
    events, index = tape_data
    if index >= len(events):
        raise ValueError("Random tape exhausted")
    event = events[index]
    return event, (events, index + 1)

def get_empty_positions(board):
    """Get list of empty positions as (idx) tuples."""
    empty = []
    for i in range(16):
        if ((board >> (4*i)) & 0xF) == 0:
            empty.append(i)
    return empty

def add_tile_deterministic(board, tape_data):
    """Add tile using tape instead of RNG."""
    empty_cells = get_empty_positions(board)
    if not empty_cells:
        return board, tape_data
    
    event, new_tape_data = get_next_event(tape_data)
    position, value = event
    
    # Map tape position to actual empty cell
    actual_idx = empty_cells[position % len(empty_cells)]
    
    # Set the tile (value: 1=2, 2=4)
    new_board = board | (value << (4 * actual_idx))
    return new_board, new_tape_data

def play_game_with_tape(program, tape_data, search_depth=2, max_moves=100):
    """Play game using deterministic tape."""
    board = 0  # Empty board
    
    # Initial tiles
    board, tape_data = add_tile_deterministic(board, tape_data)
    board, tape_data = add_tile_deterministic(board, tape_data)
    
    score = 0
    moves = 0
    
    # Initialize Game2048 tables
    Game2048._init_tables()
    
    while moves < max_moves and not Game2048.is_game_over(board):
        # Simple move selection (for testing - not using expectimax)
        best_move = None
        best_value = -float('inf')
        
        for direction, move_func in [('left', Game2048.move_left), 
                                    ('right', Game2048.move_right), 
                                    ('up', Game2048.move_up), 
                                    ('down', Game2048.move_down)]:
            new_board, move_score, moved = move_func(board)
            if moved:
                value = eval_program(program, new_board)
                if value > best_value:
                    best_value = value
                    best_move = (direction, new_board, move_score)
        
        if best_move is None:
            break
        
        direction, new_board, move_score = best_move
        score += move_score
        board, tape_data = add_tile_deterministic(new_board, tape_data)
        moves += 1
    
    # Find max tile value
    max_tile_log = 0
    for i in range(16):
        cell_value = (board >> (i * 4)) & 0xF
        if cell_value > max_tile_log:
            max_tile_log = cell_value
    
    max_tile = 0 if max_tile_log == 0 else (1 << max_tile_log)
    
    return score, max_tile, tape_data[1]  # Return index too

def test_with_tape(tape_file):
    """Test deterministic gameplay."""
    print(f"Loading random tape from {tape_file}...")
    events, _ = load_random_tape(tape_file)
    print(f"Loaded {len(events)} random events\n")
    
    # Create simple test program matching OCaml version
    # Mul(Add(NumEmptyCells, MonotonicityScore), SmoothnessScore)
    program = [
        GPNode.MUL,
        GPNode.ADD,
        GPNode.NUM_EMPTY_CELLS,
        GPNode.MONOTONICITY_SCORE,
        GPNode.SMOOTHNESS_SCORE
    ]
    
    print(f"Test program: {program}\n")
    
    print("Playing game with deterministic random tape...")
    tape_data = (events, 0)
    score, max_tile, events_used = play_game_with_tape(program, tape_data)
    
    print(f"\nGame complete!")
    print(f"Final score: {score}")
    print(f"Max tile: {max_tile}")
    print(f"Random events used: {events_used}")

if __name__ == "__main__":
    import sys
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <random_tape.txt>")
        sys.exit(1)
    
    test_with_tape(sys.argv[1])