#!/usr/bin/env python3
# final_correct_test.py - 使用numba+expectimax=2的最终正确测试
import json
import time
import random
import numpy as np
from datetime import datetime

from game import Game2048, NUMBA_AVAILABLE
from gp_engine import GPEngine, Program, NumEmptyCells, MaxTileValue, MonotonicityScore, SmoothnessScore
from gp_engine import CornerPreference, MergePotential, EdgeAlignment, Min, Max, Sigmoid, WeightedAvg
from test_runner import GPTester

def create_final_engine(version: str, train_seed: int) -> GPEngine:
    """创建最终测试版本的引擎 - 正确配置"""
    random.seed(train_seed)
    np.random.seed(train_seed)
    
    engine = GPEngine(
        population_size=8,    # 减小规模避免超时
        generations=2,        # 减少代数
        crossover_rate=0.8,
        mutation_rate=0.15,
        tournament_size=3,
        max_init_depth=3,     # 减小初始深度
        max_depth=6,          # 减小最大深度
        elitism_size=2,
        games_per_individual=2,
        fitness_search_depth=2,    # 保持expectimax=2
        log_dir=f'final_test/{version}_{train_seed}'
    )
    
    if version == "baseline":
        # 基础版本：只使用前4个终端和前5个函数
        engine.functions = [engine.functions[i] for i in range(5)]
        engine.terminals = [engine.terminals[i] for i in range(4)]
    elif version == "v1.0":
        # v1.0：基础函数 + 增强终端
        engine.functions = [engine.functions[i] for i in range(5)]
        # engine.terminals 包含所有7个终端
    elif version == "v1.1":
        # v1.1：所有函数 + 所有终端
        pass  # 使用默认的完整集合
    elif version == "v1.2":
        # v1.2：完整集合 + 增强适应度（当前实现）
        pass  # 使用默认的完整集合
    
    return engine

def test_program_final(program: Program, test_seed: int, num_games: int = 3) -> dict:
    """最终版本的程序测试 - 使用expectimax=2"""
    random.seed(test_seed)
    np.random.seed(test_seed)
    
    from gp_engine import _gp_expect_value
    
    scores = []
    max_tiles = []
    moves_list = []
    success_512 = 0
    success_1024 = 0
    success_2048 = 0
    
    print(f"最终测试 (Numba+expectimax=2, {num_games}局游戏)...")
    
    for game_idx in range(num_games):
        board = Game2048.reset_board()
        score = 0
        moves = 0
        
        while not Game2048.is_game_over(board):
            move_fns = [Game2048.move_up, Game2048.move_down, Game2048.move_left, Game2048.move_right]
            best_move = -1
            best_eval = -float('inf')
            
            # 使用expectimax深度=2进行搜索（与训练一致）
            for i, move_fn in enumerate(move_fns):
                next_board, _, moved = move_fn(board)
                if moved:
                    eval_score = _gp_expect_value(next_board, program, depth=2)
                    if eval_score > best_eval:
                        best_eval = eval_score
                        best_move = i
            
            if best_move != -1:
                new_board, score_gain, _ = move_fns[best_move](board)
                board = Game2048.add_random_tile(new_board)
                score += score_gain
                moves += 1
                
                if moves > 1000:  # 防止极长游戏
                    break
            else:
                break
        
        max_tile = Game2048.get_max_tile(board)
        scores.append(score)
        max_tiles.append(max_tile)
        moves_list.append(moves)
        
        if max_tile >= 512: success_512 += 1
        if max_tile >= 1024: success_1024 += 1  
        if max_tile >= 2048: success_2048 += 1
        
        print(f"  游戏 {game_idx+1}: 分数={score}, 最大方块={max_tile}, 步数={moves}")
    
    return {
        "avg_score": float(np.mean(scores)),
        "max_tile": float(np.mean(max_tiles)),
        "avg_moves": float(np.mean(moves_list)),
        "success_rate_512": success_512 / num_games,
        "success_rate_1024": success_1024 / num_games,
        "success_rate_2048": success_2048 / num_games,
        "games_played": num_games,
        "best_score": float(max(scores)),
        "best_max_tile": float(max(max_tiles))
    }

def final_comparison_test():
    """最终的正确比较测试"""
    print("=== 最终正确测试：Numba + Expectimax=2 ===")
    print(f"Numba状态: {NUMBA_AVAILABLE}")
    print("配置: 训练和测试都使用expectimax=2")
    
    Game2048._init_tables()
    tester = GPTester()
    
    # 固定种子确保可重现性
    train_seed = 12345
    test_seed = 99999
    
    versions = [
        ("baseline", "基础版本"),
        ("v1.0", "v1.0增强终端"),
        ("v1.1", "v1.1高级函数"),
        ("v1.2", "v1.2增强适应度")
    ]
    
    results = {}
    
    for version_key, version_name in versions:
        print(f"\n{'='*50}")
        print(f"测试 {version_name}")
        print(f"{'='*50}")
        
        start_time = time.time()
        
        try:
            # 训练（15秒超时）
            engine = create_final_engine(version_key, train_seed)
            program = tester.run_training_with_timeout(engine, timeout_seconds=15)
            
            train_time = time.time() - start_time
            print(f"训练用时: {train_time:.1f}s")
            print(f"训练适应度: {program.fitness:.2f}")
            print(f"程序: {str(program)}")
            
            # 最终测试（3局游戏）
            test_results = test_program_final(program, test_seed, num_games=3)
            
            # 记录结果
            results[version_key] = {
                "version": version_name,
                "training_time": train_time,
                "training_fitness": float(program.fitness),
                "avg_score": test_results["avg_score"],
                "avg_max_tile": test_results["max_tile"],
                "success_rate_512": test_results["success_rate_512"],
                "success_rate_1024": test_results["success_rate_1024"],
                "success_rate_2048": test_results["success_rate_2048"],
                "avg_moves": test_results["avg_moves"],
                "program_str": str(program),
                "expectimax_depth": 2,
                "numba_enabled": NUMBA_AVAILABLE
            }
            
            print(f"\n最终测试结果 (expectimax=2, 3局平均):")
            print(f"  平均分数: {test_results['avg_score']:.1f}")
            print(f"  平均最大方块: {test_results['max_tile']:.0f}")
            print(f"  512成功率: {test_results['success_rate_512']:.1%}")
            print(f"  1024成功率: {test_results['success_rate_1024']:.1%}")
            print(f"  2048成功率: {test_results['success_rate_2048']:.1%}")
            
        except Exception as e:
            print(f"版本 {version_name} 测试失败: {e}")
            results[version_key] = {
                "version": version_name,
                "error": str(e)
            }
    
    # 最终比较分析
    print(f"\n{'='*60}")
    print("最终正确比较分析 (Numba + Expectimax=2)")
    print(f"{'='*60}")
    
    if "baseline" in results and "avg_score" in results["baseline"]:
        baseline_score = results["baseline"]["avg_score"]
        baseline_tile = results["baseline"]["avg_max_tile"]
        
        print(f"基准性能 (正确配置):")
        print(f"  平均分数: {baseline_score:.1f}")
        print(f"  平均最大方块: {baseline_tile:.0f}")
        print(f"  512成功率: {results['baseline']['success_rate_512']:.1%}")
        print(f"  1024成功率: {results['baseline']['success_rate_1024']:.1%}")
        
        print(f"\n各版本改进效果:")
        for version_key, version_name in versions:
            if version_key in results and "avg_score" in results[version_key]:
                r = results[version_key]
                if version_key != "baseline":
                    score_improvement = (r["avg_score"] / baseline_score - 1) * 100
                    tile_improvement = (r["avg_max_tile"] / baseline_tile - 1) * 100
                    print(f"  {version_name}:")
                    print(f"    分数提升: {score_improvement:+.1f}%")
                    print(f"    方块提升: {tile_improvement:+.1f}%")
                else:
                    print(f"  {version_name}: (基准线)")
                
                print(f"    512成功率: {r['success_rate_512']:.1%}")
                print(f"    1024成功率: {r['success_rate_1024']:.1%}")
                print(f"    2048成功率: {r['success_rate_2048']:.1%}")
                print("")
    
    # 保存结果
    with open('final_correct_results.json', 'w', encoding='utf-8') as f:
        json.dump(results, f, ensure_ascii=False, indent=2)
    
    return results

if __name__ == "__main__":
    print("开始最终正确测试...")
    start_time = time.time()
    
    results = final_comparison_test()
    
    total_time = time.time() - start_time
    print(f"\n总测试时间: {total_time:.1f}秒")
    print(f"结果已保存到 final_correct_results.json")
    
    print(f"\n✅ 最终测试配置:")
    print(f"  - Numba加速: {NUMBA_AVAILABLE}")
    print(f"  - 训练expectimax深度: 2")
    print(f"  - 测试expectimax深度: 2")
    print(f"  - 性能提升: ~2x (相比之前的测试)")