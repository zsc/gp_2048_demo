#!/usr/bin/env python3
# quick_numba_test.py - 快速测试numba加速效果
import time
import random
import numpy as np
from game import Game2048

def quick_numba_benchmark():
    """快速测试numba对游戏模拟的加速效果"""
    print("=== Numba加速效果测试 ===")
    
    # 初始化
    Game2048._init_tables()
    
    # 生成测试数据 - 少量样本避免JIT编译时间
    print("生成测试数据...")
    test_boards = []
    for _ in range(50):  # 只用50个测试样本
        board = Game2048.reset_board()
        # 随机移动几步获得不同的棋盘状态
        for _ in range(random.randint(5, 15)):
            moves = [Game2048.move_up, Game2048.move_down, 
                    Game2048.move_left, Game2048.move_right]
            move = random.choice(moves)
            new_board, _, moved = move(board)
            if moved:
                board = Game2048.add_random_tile(new_board)
            if Game2048.is_game_over(board):
                break
        test_boards.append(board)
    
    print(f"测试数据准备完成：{len(test_boards)}个棋盘状态")
    
    # 预热JIT编译 - 运行几次让numba编译
    print("JIT预热...")
    for i in range(5):
        board = test_boards[i]
        Game2048.move_left(board)
        Game2048.move_right(board)
        Game2048.move_up(board)
        Game2048.move_down(board)
        Game2048.is_game_over(board)
        Game2048.get_max_tile(board)
    
    # 实际性能测试
    print("开始性能测试...")
    
    operations = 0
    start_time = time.time()
    
    for board in test_boards:
        # 模拟一次完整的移动评估
        Game2048.move_left(board)
        Game2048.move_right(board)
        Game2048.move_up(board) 
        Game2048.move_down(board)
        Game2048.is_game_over(board)
        Game2048.get_max_tile(board)
        operations += 6
    
    total_time = time.time() - start_time
    ops_per_sec = operations / total_time
    
    print(f"\n性能结果:")
    print(f"  总操作数: {operations}")
    print(f"  总时间: {total_time:.4f}秒")
    print(f"  操作/秒: {ops_per_sec:.0f}")
    print(f"  每次游戏移动评估: {(total_time/len(test_boards)*1000):.2f}ms")
    
    return ops_per_sec

def simulate_expectimax_game(depth=1, num_games=3):
    """模拟使用expectimax的游戏性能"""
    from gp_engine import Program, NumEmptyCells, _gp_expect_value
    
    print(f"\n=== Expectimax深度{depth}游戏模拟 ===")
    
    # 创建简单的测试程序
    program = Program([NumEmptyCells()])
    
    total_time = 0
    total_moves = 0
    total_score = 0
    
    for game_idx in range(num_games):
        print(f"游戏 {game_idx+1}/{num_games}")
        
        board = Game2048.reset_board()
        score = 0
        moves = 0
        
        game_start = time.time()
        
        while not Game2048.is_game_over(board) and moves < 200:  # 限制最大步数
            move_fns = [Game2048.move_up, Game2048.move_down, 
                       Game2048.move_left, Game2048.move_right]
            best_move = -1
            best_eval = -float('inf')
            
            for i, move_fn in enumerate(move_fns):
                next_board, _, moved = move_fn(board)
                if moved:
                    if depth > 0:
                        eval_score = _gp_expect_value(next_board, program, depth)
                    else:
                        eval_score = program.eval(next_board)
                    
                    if eval_score > best_eval:
                        best_eval = eval_score
                        best_move = i
            
            if best_move != -1:
                new_board, score_gain, _ = move_fns[best_move](board)
                board = Game2048.add_random_tile(new_board)
                score += score_gain
                moves += 1
            else:
                break
        
        game_time = time.time() - game_start
        max_tile = Game2048.get_max_tile(board)
        
        print(f"  分数: {score}, 最大方块: {max_tile}, 步数: {moves}, 时间: {game_time:.2f}s")
        
        total_time += game_time
        total_moves += moves
        total_score += score
    
    avg_time_per_game = total_time / num_games
    avg_moves_per_game = total_moves / num_games
    avg_score = total_score / num_games
    avg_time_per_move = total_time / total_moves if total_moves > 0 else 0
    
    print(f"\n平均结果 (深度{depth}):")
    print(f"  平均游戏时间: {avg_time_per_game:.2f}s")
    print(f"  平均步数: {avg_moves_per_game:.1f}")
    print(f"  平均分数: {avg_score:.1f}")
    print(f"  每步平均时间: {avg_time_per_move*1000:.1f}ms")
    
    return {
        'avg_time_per_game': avg_time_per_game,
        'avg_moves_per_game': avg_moves_per_game,
        'avg_score': avg_score,
        'avg_time_per_move': avg_time_per_move
    }

if __name__ == "__main__":
    print("Numba可用:", hasattr(Game2048, 'NUMBA_AVAILABLE'))
    
    # 基础操作性能测试
    ops_per_sec = quick_numba_benchmark()
    
    # Expectimax性能测试
    depth1_stats = simulate_expectimax_game(depth=1, num_games=3)
    depth2_stats = simulate_expectimax_game(depth=2, num_games=2)  # 深度2只测2局
    
    print(f"\n=== 总结 ===")
    print(f"基础操作性能: {ops_per_sec:.0f} ops/sec")
    print(f"Expectimax深度1: {depth1_stats['avg_time_per_move']*1000:.1f}ms/步")
    print(f"Expectimax深度2: {depth2_stats['avg_time_per_move']*1000:.1f}ms/步")
    
    slowdown = depth2_stats['avg_time_per_move'] / depth1_stats['avg_time_per_move']
    print(f"深度2相对深度1减速: {slowdown:.1f}x")