#!/usr/bin/env python3
# realistic_numba_test.py - 真实游戏场景下的numba效果测试
import time
from game import Game2048
from gp_engine import Program, NumEmptyCells, _gp_expect_value

def play_full_game_with_expectimax(depth=2, max_moves=300):
    """玩一局完整的expectimax游戏，统计所有操作"""
    program = Program([NumEmptyCells()])
    
    board = Game2048.reset_board()
    score = 0
    moves = 0
    
    # 统计各种操作的调用次数
    move_calls = 0
    is_game_over_calls = 0
    get_max_tile_calls = 0
    expectimax_calls = 0
    
    start_time = time.time()
    
    while moves < max_moves:
        # 检查游戏是否结束
        is_game_over_calls += 1
        if Game2048.is_game_over(board):
            break
        
        move_fns = [Game2048.move_up, Game2048.move_down, 
                   Game2048.move_left, Game2048.move_right]
        best_move = -1
        best_eval = -float('inf')
        
        # Expectimax搜索
        for i, move_fn in enumerate(move_fns):
            move_calls += 1
            next_board, _, moved = move_fn(board)
            if moved:
                expectimax_calls += 1
                eval_score = _gp_expect_value(next_board, program, depth)
                
                if eval_score > best_eval:
                    best_eval = eval_score
                    best_move = i
        
        if best_move != -1:
            move_calls += 1
            new_board, score_gain, _ = move_fns[best_move](board)
            board = Game2048.add_random_tile(new_board)
            score += score_gain
            moves += 1
        else:
            break
    
    # 最终统计
    get_max_tile_calls += 1
    max_tile = Game2048.get_max_tile(board)
    
    game_time = time.time() - start_time
    
    return {
        'score': score,
        'max_tile': max_tile,
        'moves': moves,
        'game_time': game_time,
        'move_calls': move_calls,
        'is_game_over_calls': is_game_over_calls,
        'get_max_tile_calls': get_max_tile_calls,
        'expectimax_calls': expectimax_calls
    }

def benchmark_realistic_scenario():
    """在真实游戏场景下测试numba效果"""
    print("=== 真实游戏场景Numba测试 ===")
    print("场景: Expectimax深度2的完整游戏")
    
    # JIT预热
    print("JIT预热...")
    warmup_game = play_full_game_with_expectimax(depth=1, max_moves=50)
    print(f"预热游戏: {warmup_game['moves']}步, {warmup_game['game_time']:.2f}s")
    
    # 实际测试
    print("\n开始性能测试...")
    
    num_games = 3  # 少数几局避免太长时间
    total_stats = {
        'total_time': 0,
        'total_moves': 0,
        'total_score': 0,
        'total_operations': 0
    }
    
    for game_idx in range(num_games):
        print(f"游戏 {game_idx+1}/{num_games}...")
        
        stats = play_full_game_with_expectimax(depth=2, max_moves=200)
        
        total_stats['total_time'] += stats['game_time']
        total_stats['total_moves'] += stats['moves']
        total_stats['total_score'] += stats['score']
        
        # 计算总操作数
        operations = (stats['move_calls'] + stats['is_game_over_calls'] + 
                     stats['get_max_tile_calls'])
        total_stats['total_operations'] += operations
        
        print(f"  分数: {stats['score']}, 最大方块: {stats['max_tile']}")
        print(f"  步数: {stats['moves']}, 时间: {stats['game_time']:.2f}s")
        print(f"  操作数: {operations} (移动: {stats['move_calls']}, 检测: {stats['is_game_over_calls']})")
    
    # 性能汇总
    avg_time_per_game = total_stats['total_time'] / num_games
    avg_moves_per_game = total_stats['total_moves'] / num_games
    avg_score = total_stats['total_score'] / num_games
    
    ops_per_second = total_stats['total_operations'] / total_stats['total_time']
    time_per_move = total_stats['total_time'] / total_stats['total_moves']
    
    print(f"\n性能总结:")
    print(f"  平均游戏时间: {avg_time_per_game:.2f}s")
    print(f"  平均步数: {avg_moves_per_game:.1f}")
    print(f"  平均分数: {avg_score:.0f}")
    print(f"  每步时间: {time_per_move*1000:.1f}ms")
    print(f"  操作效率: {ops_per_second:.0f} ops/s")
    print(f"  总操作数: {total_stats['total_operations']}")
    
    return {
        'avg_time_per_game': avg_time_per_game,
        'avg_moves_per_game': avg_moves_per_game,
        'ops_per_second': ops_per_second,
        'time_per_move': time_per_move
    }

if __name__ == "__main__":
    from game import NUMBA_AVAILABLE
    print(f"Numba状态: {NUMBA_AVAILABLE}")
    
    results = benchmark_realistic_scenario()
    
    print(f"\n关键性能指标:")
    print(f"  游戏操作效率: {results['ops_per_second']:.0f} ops/s")
    print(f"  Expectimax每步耗时: {results['time_per_move']*1000:.1f}ms")
    
    # 基于之前测试的expectimax=2性能做比较
    previous_time_per_move = 9.7  # ms，来自之前的测试
    current_time_per_move = results['time_per_move'] * 1000
    
    if current_time_per_move < previous_time_per_move:
        speedup = previous_time_per_move / current_time_per_move
        print(f"  相比之前测试加速: {speedup:.1f}x")
    else:
        print(f"  性能与之前测试相当")
    
    print(f"\n注意: Numba的主要优势在于:")
    print(f"  1. 大量重复调用的函数(如game_over检测)")
    print(f"  2. 数值密集的计算循环") 
    print(f"  3. 避免Python解释器开销")