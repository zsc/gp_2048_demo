#!/usr/bin/env python3
# quick_test.py - 快速验证测试方法论的正确性
import json
import time
import random
import numpy as np
from datetime import datetime

from game import Game2048
from gp_engine import GPEngine, Program, NumEmptyCells, MaxTileValue, MonotonicityScore, SmoothnessScore
from test_runner import GPTester

def quick_baseline_test():
    """快速测试基础版本以验证方法论"""
    print("=== 快速基础版本测试 ===")
    print("验证统计稳健性和随机种子分离")
    
    Game2048._init_tables()
    tester = GPTester()
    
    # 训练种子: 12345 (用于GP进化)
    train_seed = 12345
    test_seed = 99999  # 完全独立的测试种子
    
    print(f"\n1. 训练阶段 (种子: {train_seed})")
    random.seed(train_seed)
    np.random.seed(train_seed)
    
    # 创建基础版本引擎
    engine = GPEngine(
        population_size=10,  # 更小规模用于快速测试
        generations=2,       # 只运行2代
        crossover_rate=0.8,
        mutation_rate=0.15, 
        tournament_size=3,
        max_init_depth=3,
        max_depth=5,
        elitism_size=1,
        games_per_individual=1,  # 每个个体只玩1局游戏
        fitness_search_depth=1,
        log_dir='quick_test_run'
    )
    
    # 基础版本：只使用前4个终端和前5个函数
    engine.functions = [engine.functions[i] for i in range(5)]
    engine.terminals = [engine.terminals[i] for i in range(4)]
    
    try:
        program = tester.run_training_with_timeout(engine, timeout_seconds=30)
        print(f"训练完成! 最佳程序适应度: {program.fitness:.2f}")
        print(f"程序结构: {str(program)}")
        
        print(f"\n2. 测试阶段 (种子: {test_seed}, 完全独立)")
        # 使用10局游戏评估统计稳健性
        test_results = tester.test_program(program, test_seed, num_games=10)
        
        print(f"\n3. 统计结果分析:")
        print(f"  平均分数: {test_results['avg_score']:.1f} (10局平均)")
        print(f"  平均最大方块: {test_results['max_tile']:.0f} (10局平均)")
        print(f"  最高单局分数: {test_results['best_score']:.0f} (仅参考)")
        print(f"  最大单局方块: {test_results['best_max_tile']:.0f} (仅参考)")
        print(f"  512成功率: {test_results['success_rate_512']:.1%}")
        print(f"  平均步数: {test_results['avg_moves']:.0f}")
        
        print(f"\n4. 方法论验证:")
        print(f"  ✅ 使用独立随机种子 (训练:{train_seed} vs 测试:{test_seed})")
        print(f"  ✅ 统计稳健性评估 (10局游戏平均)")
        print(f"  ✅ 多指标综合评价 (分数+方块+成功率)")
        
        return test_results
        
    except Exception as e:
        print(f"测试失败: {e}")
        return None

if __name__ == "__main__":
    results = quick_baseline_test()
    if results:
        print(f"\n方法论验证成功! 可以进行完整测试套件。")
    else:
        print(f"\n方法论需要调整，请检查实现。")