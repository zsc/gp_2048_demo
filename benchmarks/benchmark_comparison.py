#!/usr/bin/env python
"""Benchmark comparison between Python and OCaml implementations."""

import time
from game import Game2048
from expectimax_python import max_value, expect_value, get_best_move

def simple_eval(board):
    """Simple evaluation function for benchmarking."""
    empty_count = sum(1 for i in range(16) if ((board >> (4*i)) & 0xF) == 0)
    max_tile = 0
    for i in range(16):
        cell = (board >> (4*i)) & 0xF
        if cell > max_tile:
            max_tile = cell
    return float(empty_count) + float(max_tile)

def load_tape(filename):
    """Load random tape."""
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
    return events

def add_tile_from_tape(board, position, value):
    """Add tile at specific position with specific value."""
    empty_positions = []
    for i in range(16):
        if ((board >> (4*i)) & 0xF) == 0:
            empty_positions.append(i)
    
    if not empty_positions:
        return board
    
    # Map tape position to actual empty cell
    actual_idx = empty_positions[position % len(empty_positions)]
    return board | (value << (4 * actual_idx))

def benchmark_expectimax(initial_board, num_iterations, search_depth):
    """Benchmark expectimax algorithm."""
    Game2048._init_tables()
    
    start_time = time.time()
    
    for _ in range(num_iterations):
        # Just compute the value, no actual moves
        value = max_value(initial_board, simple_eval, search_depth)
    
    end_time = time.time()
    elapsed = end_time - start_time
    
    return elapsed, value

def benchmark_game_with_tape(initial_board, tape_events, num_moves, search_depth):
    """Benchmark a deterministic game with tape."""
    Game2048._init_tables()
    
    start_time = time.time()
    
    board = initial_board
    tape_idx = 0
    score = 0
    moves_made = 0
    
    # Add initial tiles
    if tape_idx < len(tape_events):
        pos, val = tape_events[tape_idx]
        board = add_tile_from_tape(board, pos, val)
        tape_idx += 1
    
    if tape_idx < len(tape_events):
        pos, val = tape_events[tape_idx]
        board = add_tile_from_tape(board, pos, val)
        tape_idx += 1
    
    # Play game
    for move_num in range(num_moves):
        if Game2048.is_game_over(board):
            break
            
        move_name, _ = get_best_move(board, simple_eval, search_depth)
        if move_name is None:
            break
        
        # Execute move
        if move_name == 'up':
            board, move_score, moved = Game2048.move_up(board)
        elif move_name == 'down':
            board, move_score, moved = Game2048.move_down(board)
        elif move_name == 'left':
            board, move_score, moved = Game2048.move_left(board)
        elif move_name == 'right':
            board, move_score, moved = Game2048.move_right(board)
        
        if not moved:
            break
            
        score += move_score
        moves_made += 1
        
        # Add random tile from tape
        if tape_idx < len(tape_events):
            pos, val = tape_events[tape_idx]
            board = add_tile_from_tape(board, pos, val)
            tape_idx += 1
    
    end_time = time.time()
    elapsed = end_time - start_time
    
    return elapsed, board, score, moves_made

def main():
    print("Python Benchmark")
    print("=" * 50)
    
    # Test boards
    test_boards = [
        (0x0000000000000000, "empty"),
        (0x0000000000001234, "simple"),
        (0x1234567890ABCDEF, "complex"),
    ]
    
    # Benchmark expectimax
    print("\nExpectimax Benchmark (100 iterations):")
    for board, name in test_boards:
        for depth in [1, 2]:
            elapsed, value = benchmark_expectimax(board, 100, depth)
            print(f"  {name} board, depth {depth}: {elapsed:.3f}s (value: {value:.2f})")
    
    # Benchmark game with tape
    print("\nGame Benchmark with Tape:")
    tape_events = load_tape("test_tape.txt")
    
    for depth in [1, 2]:
        elapsed, final_board, score, moves = benchmark_game_with_tape(
            0x0000000000000000, tape_events, 50, depth
        )
        print(f"  Depth {depth}: {elapsed:.3f}s")
        print(f"    Final board: {final_board:016x}")
        print(f"    Score: {score}, Moves: {moves}")

if __name__ == "__main__":
    main()