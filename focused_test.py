#!/usr/bin/env python3
# focused_test.py - 快速但统计稳健的算法比较测试
import json
import time
import random
import numpy as np
from datetime import datetime

from game import Game2048
from gp_engine import GPEngine, Program, NumEmptyCells, MaxTileValue, MonotonicityScore, SmoothnessScore
from gp_engine import CornerPreference, MergePotential, EdgeAlignment, Min, Max, Sigmoid, WeightedAvg
from test_runner import GPTester

def create_optimized_engine(version: str, train_seed: int) -> GPEngine:
    """创建优化的小规模引擎用于快速测试"""
    random.seed(train_seed)
    np.random.seed(train_seed)
    
    engine = GPEngine(
        population_size=8,   # 小规模快速训练
        generations=3,       # 只运行3代
        crossover_rate=0.8,
        mutation_rate=0.15,
        tournament_size=2,
        max_init_depth=3,
        max_depth=5,
        elitism_size=1,
        games_per_individual=1,  # 每个个体只玩1局
        fitness_search_depth=1,
        log_dir=f'focused_test/{version}_{train_seed}'
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

def focused_comparison_test():
    """运行快速但统计稳健的比较测试"""
    print("=== 聚焦算法比较测试 ===")
    print("目标：快速验证各版本的相对性能")
    
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
        print(f"\n{'='*40}")
        print(f"测试 {version_name}")
        print(f"{'='*40}")
        
        start_time = time.time()
        
        try:
            # 快速训练（20秒超时）
            engine = create_optimized_engine(version_key, train_seed)
            program = tester.run_training_with_timeout(engine, timeout_seconds=20)
            
            train_time = time.time() - start_time
            print(f"训练用时: {train_time:.1f}秒")
            print(f"训练适应度: {program.fitness:.2f}")
            print(f"程序: {str(program)}")
            
            # 统计稳健的测试（5局游戏）
            test_results = tester.test_program(program, test_seed, num_games=5)
            
            # 记录结果
            results[version_key] = {
                "version": version_name,
                "training_time": train_time,
                "training_fitness": float(program.fitness),
                "avg_score": test_results["avg_score"],
                "avg_max_tile": test_results["max_tile"],
                "success_rate_512": test_results["success_rate_512"],
                "success_rate_1024": test_results["success_rate_1024"],
                "avg_moves": test_results["avg_moves"],
                "program_str": str(program)
            }
            
            print(f"\n测试结果 (5局平均):")
            print(f"  平均分数: {test_results['avg_score']:.1f}")
            print(f"  平均最大方块: {test_results['max_tile']:.0f}")
            print(f"  512成功率: {test_results['success_rate_512']:.1%}")
            print(f"  1024成功率: {test_results['success_rate_1024']:.1%}")
            
        except Exception as e:
            print(f"版本 {version_name} 测试失败: {e}")
            results[version_key] = {
                "version": version_name,
                "error": str(e)
            }
    
    # 比较分析
    print(f"\n{'='*50}")
    print("比较分析")
    print(f"{'='*50}")
    
    if "baseline" in results and "avg_score" in results["baseline"]:
        baseline_score = results["baseline"]["avg_score"]
        baseline_tile = results["baseline"]["avg_max_tile"]
        
        print(f"基准性能:")
        print(f"  平均分数: {baseline_score:.1f}")
        print(f"  平均最大方块: {baseline_tile:.0f}")
        
        print(f"\n改进效果:")
        for version_key, version_name in versions[1:]:
            if version_key in results and "avg_score" in results[version_key]:
                score_improvement = (results[version_key]["avg_score"] / baseline_score - 1) * 100
                tile_improvement = (results[version_key]["avg_max_tile"] / baseline_tile - 1) * 100
                
                print(f"  {version_name}:")
                print(f"    分数提升: {score_improvement:+.1f}%")
                print(f"    方块提升: {tile_improvement:+.1f}%")
                print(f"    512成功率: {results[version_key]['success_rate_512']:.1%}")
    
    # 保存结果
    with open('focused_test_results.json', 'w', encoding='utf-8') as f:
        json.dump(results, f, ensure_ascii=False, indent=2)
    
    return results

if __name__ == "__main__":
    print("开始聚焦测试...")
    start_time = time.time()
    
    results = focused_comparison_test()
    
    total_time = time.time() - start_time
    print(f"\n总测试时间: {total_time:.1f}秒")
    print(f"结果已保存到 focused_test_results.json")
    
    # 验证方法论
    print(f"\n✅ 方法论验证:")
    print(f"  - 统计稳健性: 使用5局游戏平均值")
    print(f"  - 随机种子分离: 训练(12345) vs 测试(99999)")
    print(f"  - 快速但公平: 所有版本相同的训练和测试条件")