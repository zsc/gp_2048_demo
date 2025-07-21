#!/usr/bin/env python3
# test_runner.py - 系统性测试不同版本的GP算法
import json
import time
import random
import numpy as np
from datetime import datetime
import signal
import sys
from typing import Dict, Any, List

# 导入需要的模块
from game import Game2048
from gp_engine import GPEngine, Program, NumEmptyCells, MaxTileValue, MonotonicityScore, SmoothnessScore
from gp_engine import CornerPreference, MergePotential, EdgeAlignment, Min, Max, Sigmoid, WeightedAvg

class TimeoutException(Exception):
    pass

def timeout_handler(signum, frame):
    raise TimeoutException("训练超时")

class GPTester:
    def __init__(self):
        self.results = {}
        Game2048._init_tables()
    
    def create_baseline_engine(self, train_seed: int) -> GPEngine:
        """创建基础版本GP引擎"""
        random.seed(train_seed)
        np.random.seed(train_seed)
        
        engine = GPEngine(
            population_size=20,  # 较小规模用于快速测试
            generations=5,       # 较少代数用于1分钟限制
            crossover_rate=0.8,
            mutation_rate=0.15,
            tournament_size=3,
            max_init_depth=3,
            max_depth=6,
            elitism_size=2,
            games_per_individual=2,  # 减少游戏数量加快测试
            fitness_search_depth=1,
            log_dir=f'test_runs/baseline_{train_seed}'
        )
        
        # 手动设置基础版本的节点集合
        engine.functions = [engine.functions[i] for i in range(5)]  # 只保留前5个基础函数
        engine.terminals = [engine.terminals[i] for i in range(4)]  # 只保留前4个基础终端
        
        return engine
    
    def create_v10_engine(self, train_seed: int) -> GPEngine:
        """创建v1.0增强终端节点版本"""
        random.seed(train_seed)
        np.random.seed(train_seed)
        
        engine = GPEngine(
            population_size=20,
            generations=5,
            crossover_rate=0.8,
            mutation_rate=0.15,
            tournament_size=3,
            max_init_depth=3,
            max_depth=6,
            elitism_size=2,
            games_per_individual=2,
            fitness_search_depth=1,
            log_dir=f'test_runs/v10_{train_seed}'
        )
        
        # 保留基础函数 + 增强终端节点
        engine.functions = [engine.functions[i] for i in range(5)]  # 基础函数
        # engine.terminals 已包含所有7个终端节点
        
        return engine
    
    def create_v11_engine(self, train_seed: int) -> GPEngine:
        """创建v1.1高级函数节点版本"""
        random.seed(train_seed)
        np.random.seed(train_seed)
        
        engine = GPEngine(
            population_size=20,
            generations=5,
            crossover_rate=0.8,
            mutation_rate=0.15,
            tournament_size=3,
            max_init_depth=3,
            max_depth=6,
            elitism_size=2,
            games_per_individual=2,
            fitness_search_depth=1,
            log_dir=f'test_runs/v11_{train_seed}'
        )
        
        # 包含所有函数和终端节点
        # engine.functions 和 engine.terminals 已包含所有节点
        
        return engine
    
    def create_v12_engine(self, train_seed: int) -> GPEngine:
        """创建v1.2增强适应度函数版本"""
        # 这个版本使用完整的当前实现，包含增强适应度函数
        return self.create_v11_engine(train_seed)
    
    def run_training_with_timeout(self, engine: GPEngine, timeout_seconds: int = 60) -> Program:
        """在指定超时时间内运行训练"""
        signal.signal(signal.SIGALRM, timeout_handler)
        signal.alarm(timeout_seconds)
        
        try:
            print(f"开始训练 (超时: {timeout_seconds}秒)...")
            start_time = time.time()
            
            # 运行GP进化
            engine._initialize_population()
            
            for gen in range(engine.generations):
                print(f"  代数 {gen+1}/{engine.generations}")
                
                # 评估适应度
                eval_args = [(p, engine.games_per_individual, engine.fitness_search_depth) 
                           for p in engine.population]
                
                # 简化并行处理，避免超时问题
                from gp_engine import evaluate_fitness_worker
                results = []
                for args in eval_args:
                    result = evaluate_fitness_worker(args)
                    results.append(result)
                
                engine.population = results
                engine.population.sort(key=lambda p: p.fitness, reverse=True)
                
                best = engine.population[0]
                print(f"    最佳适应度: {best.fitness:.2f}, 分数: {best.game_score:.0f}, 最大方块: {best.max_tile:.0f}")
                
                # 创建下一代
                next_generation = []
                if engine.elitism_size > 0:
                    next_generation.extend(engine.population[:engine.elitism_size])
                
                while len(next_generation) < engine.population_size:
                    p1 = engine._tournament_selection()
                    if random.random() < engine.crossover_rate:
                        p2 = engine._tournament_selection()
                        c1, c2 = engine._crossover(p1, p2)
                    else:
                        c1, c2 = p1, None
                    
                    if random.random() < engine.mutation_rate:
                        c1 = engine._mutate(c1)
                    
                    next_generation.append(c1)
                    if c2 and len(next_generation) < engine.population_size:
                        if random.random() < engine.mutation_rate:
                            c2 = engine._mutate(c2)
                        next_generation.append(c2)
                
                engine.population = next_generation
            
            end_time = time.time()
            print(f"训练完成 (用时: {end_time - start_time:.1f}秒)")
            
            # 返回最佳程序
            final_population = []
            eval_args = [(p, engine.games_per_individual, engine.fitness_search_depth) 
                        for p in engine.population]
            for args in eval_args:
                result = evaluate_fitness_worker(args)
                final_population.append(result)
            
            final_population.sort(key=lambda p: p.fitness, reverse=True)
            return final_population[0]
            
        except TimeoutException:
            print(f"训练超时 ({timeout_seconds}秒)")
            # 返回当前最佳程序
            if hasattr(engine, 'population') and engine.population:
                engine.population.sort(key=lambda p: p.fitness, reverse=True)
                return engine.population[0]
            else:
                # 返回一个简单的默认程序
                return Program([NumEmptyCells()])
        finally:
            signal.alarm(0)  # 取消超时
            engine.pool.close()
            engine.pool.join()
            engine.writer.close()
    
    def test_program(self, program: Program, test_seed: int, num_games: int = 10) -> Dict[str, Any]:
        """测试程序性能，使用独立的随机种子"""
        random.seed(test_seed)
        np.random.seed(test_seed)
        
        scores = []
        max_tiles = []
        moves_list = []
        success_512 = 0
        success_1024 = 0
        success_2048 = 0
        
        print(f"测试程序性能 ({num_games}局游戏)...")
        
        for game_idx in range(num_games):
            board = Game2048.reset_board()
            score = 0
            moves = 0
            
            while not Game2048.is_game_over(board):
                # 使用简单贪心策略进行测试
                move_fns = [Game2048.move_up, Game2048.move_down, Game2048.move_left, Game2048.move_right]
                best_move = -1
                best_eval = -float('inf')
                
                for i, move_fn in enumerate(move_fns):
                    next_board, _, moved = move_fn(board)
                    if moved:
                        eval_score = program.eval(next_board)
                        if eval_score > best_eval:
                            best_eval = eval_score
                            best_move = i
                
                if best_move != -1:
                    new_board, score_gain, _ = move_fns[best_move](board)
                    board = Game2048.add_random_tile(new_board)
                    score += score_gain
                    moves += 1
                    
                    if moves > 5000:  # 防止无限循环
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
    
    def run_test_suite(self):
        """运行完整测试套件"""
        print("=== GP 2048 算法优化测试套件 ===")
        print(f"开始时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        
        # 使用固定但不同的随机种子确保可重现性
        train_seeds = [12345, 23456, 34567, 45678]  # 训练种子
        test_seed = 99999  # 测试种子，完全独立
        
        versions = [
            ("baseline", "基础版本", self.create_baseline_engine),
            ("v1.0_enhanced_terminals", "v1.0增强终端节点", self.create_v10_engine), 
            ("v1.1_advanced_functions", "v1.1高级函数节点", self.create_v11_engine),
            ("v1.2_enhanced_fitness", "v1.2增强适应度函数", self.create_v12_engine)
        ]
        
        for version_key, version_name, create_engine_func in versions:
            print(f"\n{'='*50}")
            print(f"测试 {version_name}")
            print(f"{'='*50}")
            
            best_program = None
            best_fitness = -float('inf')
            
            # 尝试多个训练种子，选择最佳结果
            for train_seed in train_seeds:
                print(f"\n训练种子: {train_seed}")
                try:
                    engine = create_engine_func(train_seed)
                    program = self.run_training_with_timeout(engine, timeout_seconds=60)
                    
                    if program.fitness > best_fitness:
                        best_fitness = program.fitness
                        best_program = program
                        print(f"  新的最佳程序! 适应度: {best_fitness:.2f}")
                
                except Exception as e:
                    print(f"  训练失败: {e}")
                    continue
            
            if best_program is None:
                print(f"  {version_name} 训练完全失败，跳过测试")
                continue
            
            print(f"\n最佳训练结果:")
            print(f"  适应度: {best_program.fitness:.2f}")
            print(f"  程序: {str(best_program)}")
            
            # 测试最佳程序
            test_results = self.test_program(best_program, test_seed, num_games=10)
            
            # 保存结果 - 使用统计稳健的平均值而非最大值
            self.results[version_key] = {
                "version": version_name,
                "training_fitness": float(best_program.fitness),
                "program_str": str(best_program),
                "best_scores": {
                    "avg_score": test_results["avg_score"],          # 10局平均分数
                    "max_tile": test_results["max_tile"],           # 10局平均最大方块  
                    "fitness": float(best_program.fitness)          # 训练适应度
                },
                "test_results": {
                    "games_played": test_results["games_played"],
                    "success_rate_512": test_results["success_rate_512"],
                    "success_rate_1024": test_results["success_rate_1024"], 
                    "success_rate_2048": test_results["success_rate_2048"],
                    "avg_moves": test_results["avg_moves"],
                    "best_single_score": test_results["best_score"],      # 单局最高分数
                    "best_single_tile": test_results["best_max_tile"]     # 单局最大方块
                },
                "timestamp": datetime.now().isoformat()
            }
            
            print(f"\n测试结果:")
            print(f"  平均分数: {test_results['avg_score']:.1f}")
            print(f"  平均最大方块: {test_results['max_tile']:.0f}")
            print(f"  512成功率: {test_results['success_rate_512']:.1%}")
            print(f"  1024成功率: {test_results['success_rate_1024']:.1%}")
            print(f"  2048成功率: {test_results['success_rate_2048']:.1%}")
        
        print(f"\n{'='*50}")
        print("测试套件完成!")
        print(f"结束时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        
        return self.results

if __name__ == "__main__":
    tester = GPTester()
    results = tester.run_test_suite()
    
    # 保存结果到文件
    with open('test_results.json', 'w', encoding='utf-8') as f:
        json.dump(results, f, ensure_ascii=False, indent=2)
    
    print(f"\n结果已保存到 test_results.json")