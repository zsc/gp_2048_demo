#!/usr/bin/env python
"""Comprehensive benchmark comparing Python and OCaml implementations."""

import time
import subprocess
from game import Game2048
from expectimax_python import max_value, get_best_move
import random

def simple_eval(board):
    """Simple evaluation function for benchmarking."""
    empty_count = sum(1 for i in range(16) if ((board >> (4*i)) & 0xF) == 0)
    max_tile = 0
    for i in range(16):
        cell = (board >> (4*i)) & 0xF
        if cell > max_tile:
            max_tile = cell
    return float(empty_count) + float(max_tile)

def benchmark_board_operations(iterations=10000):
    """Benchmark basic board operations."""
    Game2048._init_tables()
    
    # Test boards
    boards = [
        0x0000000000000000,  # empty
        0x0000000000001234,  # simple
        0x1234567890ABCDEF,  # complex
    ]
    
    print("\n1. BOARD OPERATIONS BENCHMARK")
    print("=" * 50)
    
    # Move operations
    total_time = 0
    for board in boards:
        start = time.time()
        for _ in range(iterations):
            Game2048.move_left(board)
            Game2048.move_right(board)
            Game2048.move_up(board)
            Game2048.move_down(board)
        elapsed = time.time() - start
        total_time += elapsed
        print(f"  Board {board:016x}: {elapsed:.3f}s for {iterations*4} moves")
    
    print(f"  Total: {total_time:.3f}s for {len(boards)*iterations*4} moves")
    print(f"  Speed: {len(boards)*iterations*4/total_time:.0f} moves/sec")
    
    return total_time

def benchmark_gp_tree_evaluation(iterations=1000):
    """Benchmark GP tree evaluation."""
    print("\n2. GP TREE EVALUATION BENCHMARK")
    print("=" * 50)
    
    # Simple evaluation function as proxy for GP tree
    boards = [
        0x0000000000000000,
        0x0000000000001234,
        0x1234567890ABCDEF,
    ]
    
    total_time = 0
    for board in boards:
        start = time.time()
        for _ in range(iterations):
            simple_eval(board)
        elapsed = time.time() - start
        total_time += elapsed
        print(f"  Board {board:016x}: {elapsed:.3f}s for {iterations} evaluations")
    
    print(f"  Total: {total_time:.3f}s for {len(boards)*iterations} evaluations")
    print(f"  Speed: {len(boards)*iterations/total_time:.0f} evals/sec")
    
    return total_time

def benchmark_expectimax(iterations=10):
    """Benchmark expectimax search."""
    print("\n3. EXPECTIMAX SEARCH BENCHMARK")
    print("=" * 50)
    
    boards = [
        0x0000000000000000,
        0x0000000000001234,
        0x1234567890ABCDEF,
    ]
    
    for depth in [1, 2, 3]:
        print(f"\n  Depth {depth}:")
        total_time = 0
        for board in boards:
            start = time.time()
            for _ in range(iterations):
                max_value(board, simple_eval, depth)
            elapsed = time.time() - start
            total_time += elapsed
            print(f"    Board {board:016x}: {elapsed:.3f}s")
        
        print(f"    Total: {total_time:.3f}s for {len(boards)*iterations} searches")
        if total_time > 0:
            print(f"    Speed: {len(boards)*iterations/total_time:.1f} searches/sec")

def benchmark_full_game(num_games=10):
    """Benchmark full game playing."""
    print("\n4. FULL GAME BENCHMARK")
    print("=" * 50)
    
    Game2048._init_tables()
    random.seed(42)
    
    depths = [1, 2]
    for depth in depths:
        total_score = 0
        total_moves = 0
        start = time.time()
        
        for _ in range(num_games):
            board = 0
            board = Game2048.add_random_tile(board)
            board = Game2048.add_random_tile(board)
            
            score = 0
            moves = 0
            
            while not Game2048.is_game_over(board) and moves < 100:
                move_name, _ = get_best_move(board, simple_eval, depth)
                if move_name is None:
                    break
                
                if move_name == 'up':
                    board, move_score, moved = Game2048.move_up(board)
                elif move_name == 'down':
                    board, move_score, moved = Game2048.move_down(board)
                elif move_name == 'left':
                    board, move_score, moved = Game2048.move_left(board)
                elif move_name == 'right':
                    board, move_score, moved = Game2048.move_right(board)
                
                if moved:
                    score += move_score
                    moves += 1
                    board = Game2048.add_random_tile(board)
            
            total_score += score
            total_moves += moves
        
        elapsed = time.time() - start
        avg_score = total_score / num_games
        avg_moves = total_moves / num_games
        
        print(f"\n  Depth {depth}:")
        print(f"    Time: {elapsed:.3f}s for {num_games} games")
        print(f"    Speed: {num_games/elapsed:.1f} games/sec")
        print(f"    Avg score: {avg_score:.0f}")
        print(f"    Avg moves: {avg_moves:.0f}")

def benchmark_gp_evolution():
    """Benchmark GP evolution."""
    print("\n5. GP EVOLUTION BENCHMARK")
    print("=" * 50)
    print("  (Skipped - would require full GP engine setup)")

def run_ocaml_benchmark():
    """Run the OCaml benchmark and parse results."""
    print("\n" + "="*60)
    print("OCAML BENCHMARK RESULTS")
    print("="*60)
    
    try:
        # Run the comprehensive OCaml benchmark
        result = subprocess.run(
            ["dune", "exec", "./benchmark_comprehensive.exe"],
            capture_output=True,
            text=True,
            check=True
        )
        print(result.stdout)
    except subprocess.CalledProcessError as e:
        print(f"Error running OCaml benchmark: {e}")
        print(f"Stdout: {e.stdout}")
        print(f"Stderr: {e.stderr}")

def main():
    print("COMPREHENSIVE PERFORMANCE COMPARISON: Python vs OCaml")
    print("="*60)
    print("\nPYTHON BENCHMARK RESULTS")
    print("="*60)
    
    # Python benchmarks
    benchmark_board_operations()
    benchmark_gp_tree_evaluation()
    benchmark_expectimax()
    benchmark_full_game()
    benchmark_gp_evolution()
    
    # OCaml benchmarks
    run_ocaml_benchmark()

if __name__ == "__main__":
    main()