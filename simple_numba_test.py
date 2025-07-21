#!/usr/bin/env python3
# simple_numba_test.py - 简单直接的numba效果验证
import time
from game import Game2048

def simple_performance_test():
    """简单的性能对比测试"""
    print("=== 简单Numba性能测试 ===")
    
    Game2048._init_tables()
    
    # 创建测试棋盘
    test_boards = []
    for i in range(1000):
        board = Game2048.reset_board()
        # 做一些随机移动
        for _ in range(i % 20):
            moves = [Game2048.move_up, Game2048.move_down, 
                    Game2048.move_left, Game2048.move_right]
            import random
            move = random.choice(moves)
            new_board, _, moved = move(board)
            if moved:
                board = Game2048.add_random_tile(new_board)
        test_boards.append(board)
    
    print(f"创建了{len(test_boards)}个测试棋盘")
    
    # 预热JIT
    print("JIT预热...")
    for i in range(10):
        Game2048.get_max_tile(test_boards[i])
        Game2048.is_game_over(test_boards[i])
    
    # 测试get_max_tile性能
    print("测试get_max_tile...")
    start = time.time()
    for board in test_boards:
        Game2048.get_max_tile(board)
    get_max_time = time.time() - start
    
    # 测试is_game_over性能
    print("测试is_game_over...")
    start = time.time()
    for board in test_boards:
        Game2048.is_game_over(board)
    is_over_time = time.time() - start
    
    # 测试move操作性能
    print("测试move操作...")
    start = time.time()
    for board in test_boards[:200]:  # 移动操作较慢，只测试200个
        Game2048.move_left(board)
        Game2048.move_right(board)
    move_time = time.time() - start
    
    print(f"\n性能结果:")
    print(f"  get_max_tile: {len(test_boards)/get_max_time:.0f} ops/s")
    print(f"  is_game_over: {len(test_boards)/is_over_time:.0f} ops/s") 
    print(f"  move操作: {400/move_time:.0f} ops/s")
    
    # 整体性能估算
    total_ops = len(test_boards) * 2 + 400
    total_time = get_max_time + is_over_time + move_time
    overall_perf = total_ops / total_time
    
    print(f"  整体性能: {overall_perf:.0f} ops/s")
    
    return overall_perf

def compare_expectimax_timing():
    """比较expectimax的时间开销"""
    from gp_engine import Program, NumEmptyCells, _gp_expect_value
    
    print(f"\n=== Expectimax时间测试 ===")
    
    Game2048._init_tables()
    program = Program([NumEmptyCells()])
    
    # 创建一个中等复杂度的棋盘
    board = Game2048.reset_board()
    for _ in range(10):
        new_board, _, moved = Game2048.move_up(board)
        if moved:
            board = Game2048.add_random_tile(new_board)
    
    print("测试expectimax深度1...")
    start = time.time()
    for _ in range(10):
        _gp_expect_value(board, program, 1)
    depth1_time = (time.time() - start) / 10
    
    print("测试expectimax深度2...")
    start = time.time()
    for _ in range(3):  # 深度2较慢，只测3次
        _gp_expect_value(board, program, 2)
    depth2_time = (time.time() - start) / 3
    
    print(f"\n时间对比:")
    print(f"  深度1: {depth1_time*1000:.1f}ms")
    print(f"  深度2: {depth2_time*1000:.1f}ms")
    print(f"  深度2/深度1倍数: {depth2_time/depth1_time:.1f}x")
    
    return depth1_time, depth2_time

if __name__ == "__main__":
    from game import NUMBA_AVAILABLE
    print(f"Numba可用: {NUMBA_AVAILABLE}")
    
    # 基础性能测试
    overall_perf = simple_performance_test()
    
    # Expectimax时间测试
    d1_time, d2_time = compare_expectimax_timing()
    
    print(f"\n=== 总结 ===")
    print(f"基础游戏操作: {overall_perf:.0f} ops/s")
    print(f"Expectimax深度1: {d1_time*1000:.1f}ms")
    print(f"Expectimax深度2: {d2_time*1000:.1f}ms")
    
    # 估算完整游戏性能
    moves_per_game = 150  # 典型游戏步数
    game_time_d1 = moves_per_game * d1_time
    game_time_d2 = moves_per_game * d2_time
    
    print(f"\n估算完整游戏时间:")
    print(f"  深度1: {game_time_d1:.1f}s")
    print(f"  深度2: {game_time_d2:.1f}s")
    
    if NUMBA_AVAILABLE:
        print(f"\nNumba优化已启用!")
    else:
        print(f"\nNumba未启用，使用纯Python实现")