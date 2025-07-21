#!/usr/bin/env python3
# numba_benchmark.py - 专门测试numba加速效果
import time
import random
import numpy as np
from game import Game2048, NUMBA_AVAILABLE

def create_test_boards(count=100):
    """创建测试用的棋盘状态"""
    Game2048._init_tables()
    boards = []
    
    for _ in range(count):
        board = Game2048.reset_board()
        # 随机游戏几步
        for _ in range(random.randint(10, 50)):
            moves = [Game2048.move_up, Game2048.move_down, 
                    Game2048.move_left, Game2048.move_right]
            move = random.choice(moves)
            new_board, _, moved = move(board)
            if moved:
                board = Game2048.add_random_tile(new_board)
            if Game2048.is_game_over(board):
                break
        boards.append(board)
    
    return boards

def benchmark_functions(test_boards, warmup_rounds=5):
    """基准测试各个函数的性能"""
    print(f"Numba可用: {NUMBA_AVAILABLE}")
    print(f"测试样本数: {len(test_boards)}")
    
    # JIT预热
    if warmup_rounds > 0:
        print("JIT预热中...")
        for i in range(min(warmup_rounds, len(test_boards))):
            board = test_boards[i]
            Game2048.get_max_tile(board)
            Game2048.is_game_over(board)
    
    # 测试 get_max_tile
    print("\n测试 get_max_tile...")
    start_time = time.time()
    for board in test_boards:
        Game2048.get_max_tile(board)
    get_max_tile_time = time.time() - start_time
    
    # 测试 is_game_over  
    print("测试 is_game_over...")
    start_time = time.time()
    for board in test_boards:
        Game2048.is_game_over(board)
    is_game_over_time = time.time() - start_time
    
    # 测试移动操作
    print("测试移动操作...")
    start_time = time.time()
    for board in test_boards:
        Game2048.move_left(board)
        Game2048.move_right(board)
        Game2048.move_up(board)
        Game2048.move_down(board)
    move_operations_time = time.time() - start_time
    
    # 结果汇总
    total_time = get_max_tile_time + is_game_over_time + move_operations_time
    operations_per_second = (len(test_boards) * 6) / total_time  # 6个操作每个棋盘
    
    print(f"\n性能结果:")
    print(f"  get_max_tile: {get_max_tile_time:.4f}s ({len(test_boards)/get_max_tile_time:.0f} ops/s)")
    print(f"  is_game_over: {is_game_over_time:.4f}s ({len(test_boards)/is_game_over_time:.0f} ops/s)")
    print(f"  move_operations: {move_operations_time:.4f}s ({len(test_boards)*4/move_operations_time:.0f} ops/s)")
    print(f"  总体性能: {operations_per_second:.0f} ops/s")
    
    return {
        'get_max_tile_time': get_max_tile_time,
        'is_game_over_time': is_game_over_time,
        'move_operations_time': move_operations_time,
        'total_ops_per_sec': operations_per_second
    }

def compare_with_without_numba():
    """比较有无numba的性能差异"""
    print("=== Numba性能对比测试 ===")
    
    # 创建测试数据
    test_boards = create_test_boards(200)  # 200个测试样本
    
    # 设置随机种子确保一致性
    random.seed(42)
    np.random.seed(42)
    
    # 当前版本性能（带numba）
    current_stats = benchmark_functions(test_boards, warmup_rounds=10)
    
    # 临时关闭numba进行对比
    print(f"\n{'='*50}")
    print("模拟无numba版本性能...")
    
    # 直接测试原始Python实现的性能
    start_time = time.time()
    for board in test_boards[:50]:  # 只测试50个样本，因为原始版本较慢
        # 模拟原始get_max_tile
        m = 0
        tmp = board
        for _ in range(16):
            m = max(m, tmp & 0xF)
            tmp >>= 4
        max_tile = 0 if m==0 else (1<<m)
        
        # 模拟原始is_game_over的简化版本
        has_empty = False
        for i in range(16):
            if ((board>>(4*i)) & 0xF) == 0:
                has_empty = True
                break
        if not has_empty:
            # 简化的合并检查
            game_over = True
            for r in range(4):
                for c in range(3):
                    pos1 = r * 4 + c
                    pos2 = r * 4 + c + 1
                    val1 = (board >> (4*pos1)) & 0xF
                    val2 = (board >> (4*pos2)) & 0xF
                    if val1 > 0 and val1 == val2:
                        game_over = False
                        break
                if not game_over:
                    break
    
    python_time = time.time() - start_time
    python_ops_per_sec = 50 / python_time
    
    # 估算完整性能
    estimated_speedup = python_ops_per_sec / (current_stats['total_ops_per_sec'] / 6)
    
    print(f"\n性能对比:")
    print(f"  Numba版本: {current_stats['total_ops_per_sec']:.0f} ops/s")
    print(f"  Python版本: {python_ops_per_sec:.0f} ops/s")
    print(f"  估算加速倍数: {1/estimated_speedup:.1f}x") 
    
    return estimated_speedup

if __name__ == "__main__":
    speedup = compare_with_without_numba()
    
    print(f"\n{'='*50}")
    print(f"最终结果: Numba加速效果约为 {1/speedup:.1f}x")
    if speedup < 1:
        print("注意: 实际观察到显著加速效果")
    else:
        print("注意: 加速效果可能受JIT编译开销影响")