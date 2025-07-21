#!/usr/bin/env python3
# timed_expectimax_test.py - 带超时控制的expectimax测试

import time
import random
import numpy as np
import json
from datetime import datetime

from game import Game2048
from gp_engine import GPEngine, _gp_expect_value
from gp_engine import Add, Sub, Mul, SafeDiv, IfLTE
from gp_engine import NumEmptyCells, MaxTileValue, MonotonicityScore, SmoothnessScore
from gp_engine import CornerPreference, MergePotential, EdgeAlignment

class TimeoutController:
    def __init__(self, max_time_seconds):
        self.start_time = time.time()
        self.max_time = max_time_seconds
    
    def is_timeout(self):
        return time.time() - self.start_time > self.max_time
    
    def remaining_time(self):
        return max(0, self.max_time - (time.time() - self.start_time))

def get_dynamic_depth(board: int, strategy: str) -> int:
    """动态深度策略"""
    empty_count = sum(1 for i in range(16) if (board >> (i*4)) & 0xF == 0)
    
    if strategy == 'greedy':
        return 0
    elif strategy == 'fixed1':
        return 1
    elif strategy == 'fixed2':
        return 2
    elif strategy == 'adaptive':
        if empty_count >= 10: return 1
        elif empty_count >= 6: return 2  
        elif empty_count >= 3: return 3
        else: return 4
    elif strategy == 'smart':
        max_tile = Game2048.get_max_tile(board)
        if empty_count >= 12: return 1
        elif empty_count >= 8: return 2
        elif empty_count >= 4 and max_tile < 512: return 2
        elif empty_count >= 4: return 3
        else: return 4
    return 1

def quick_eval_strategy(program, strategy: str, timeout_ctrl: TimeoutController, max_games=10):
    """评估策略，带超时控制"""
    scores, tiles = [], []
    games_completed = 0
    
    for game in range(max_games):
        if timeout_ctrl.is_timeout():
            print(f"    超时，完成{games_completed}局")
            break
            
        board = Game2048.reset_board()
        score = 0
        moves = 0
        
        while not Game2048.is_game_over(board) and moves < 200:  # 限制最大步数
            if timeout_ctrl.is_timeout():
                break
                
            depth = get_dynamic_depth(board, strategy)
            
            move_fns = [Game2048.move_up, Game2048.move_down, 
                       Game2048.move_left, Game2048.move_right]
            best_move = -1
            best_eval = -float('inf')
            
            for i, move_fn in enumerate(move_fns):
                next_board, _, moved = move_fn(board)
                if moved:
                    if depth == 0:
                        eval_score = program.eval(next_board)
                    else:
                        eval_score = _gp_expect_value(next_board, program, depth)
                    
                    if eval_score > best_eval:
                        best_eval = eval_score
                        best_move = i
            
            if best_move >= 0:
                board, move_score, _ = move_fns[best_move](board)
                score += move_score
                moves += 1
                
                empty = [i for i in range(16) if (board >> (i*4)) & 0xF == 0]
                if empty:
                    pos = random.choice(empty)
                    tile = 1 if random.random() < 0.9 else 2
                    board |= (tile << (pos*4))
        
        scores.append(score)
        tiles.append(Game2048.get_max_tile(board))
        games_completed += 1
    
    if games_completed == 0:
        return {'avg': 0, 'max': 0, 'tile': 0, 'max_tile': 0, '512%': 0, 'games': 0}
    
    return {
        'avg': np.mean(scores),
        'max': max(scores),
        'tile': np.mean(tiles),
        'max_tile': max(tiles),
        '512%': sum(t >= 512 for t in tiles) / len(tiles) * 100,
        'games': games_completed
    }

def main():
    print("带超时控制的Expectimax策略测试")
    print("目标: 90秒内完成测试，获得可靠结果")
    print("=" * 50)
    
    total_timeout = TimeoutController(90)  # 90秒总超时
    Game2048._init_tables()
    
    # 阶段1: 快速训练v1.0模型 (最多30秒)
    print("阶段1: 快速训练v1.0...")
    train_timeout = TimeoutController(30)
    
    random.seed(2025)
    np.random.seed(2025)
    
    engine = GPEngine(
        population_size=6,      # 极小种群
        generations=4,          # 极少代数
        games_per_individual=1,
        fitness_search_depth=1,
        max_init_depth=3,
        max_depth=4,
        log_dir='timed_test/train'
    )
    
    # v1.0配置
    engine.functions = [Add(), Sub(), Mul(), SafeDiv(), IfLTE()]
    engine.terminals = [NumEmptyCells(), MaxTileValue(), MonotonicityScore(), SmoothnessScore(),
                       CornerPreference(), MergePotential(), EdgeAlignment()]
    
    train_start = time.time()
    try:
        program = engine.run()
        train_time = time.time() - train_start
        print(f"训练完成: {train_time:.1f}s, 适应度: {program.fitness:.0f}")
    except Exception as e:
        print(f"训练超时或失败，使用简单程序: {e}")
        # 创建简单程序作为备选
        from gp_engine import Program
        program = Program([Add(), CornerPreference(), MonotonicityScore()])
        program.fitness = 1000000
    
    if total_timeout.is_timeout():
        print("整体超时，退出")
        return
    
    # 阶段2: 测试不同策略 (剩余时间)
    print(f"\n阶段2: 测试Expectimax策略 (剩余{total_timeout.remaining_time():.1f}s)")
    
    strategies = {
        'greedy': '贪心（基准）',
        'fixed1': '固定深度1',
        'fixed2': '固定深度2', 
        'adaptive': '自适应深度',
        'smart': '智能策略'
    }
    
    results = []
    strategy_timeout = total_timeout.remaining_time() / len(strategies)  # 平均分配时间
    
    for strategy, desc in strategies.items():
        if total_timeout.is_timeout():
            print(f"整体超时，跳过{strategy}")
            break
            
        print(f"\n测试 {strategy} - {desc} (限时{strategy_timeout:.1f}s)")
        
        # 设置独立的评估种子
        random.seed(4000)
        np.random.seed(4000)
        
        strategy_timer = TimeoutController(strategy_timeout)
        eval_start = time.time()
        
        result = quick_eval_strategy(program, strategy, strategy_timer, max_games=8)
        eval_time = time.time() - eval_start
        
        result.update({
            'strategy': strategy,
            'desc': desc,
            'time': eval_time
        })
        results.append(result)
        
        print(f"  结果: 平均{result['avg']:.0f}分, 512率{result['512%']:.1f}%, "
              f"完成{result['games']}局, 用时{eval_time:.1f}s")
    
    # 输出结果
    if results:
        results.sort(key=lambda x: x['512%'], reverse=True)
        
        print(f"\n{'='*60}")
        print("Expectimax策略排行榜")
        print(f"{'='*60}")
        print(f"{'策略':<10} {'平均分':<8} {'512%':<6} {'最高分':<8} {'完成局数':<8}")
        print("-" * 60)
        
        for r in results:
            print(f"{r['strategy']:<10} {r['avg']:<8.0f} {r['512%']:<6.1f} "
                  f"{r['max']:<8.0f} {r['games']:<8}")
        
        # 分析结果
        greedy = next((r for r in results if r['strategy'] == 'greedy'), None)
        best = results[0]
        
        print(f"\n实验结论:")
        if greedy and best['strategy'] != 'greedy':
            improvement = best['512%'] - greedy['512%']
            print(f"1. 最佳策略: {best['strategy']} - {best['desc']}")
            print(f"2. 性能提升: +{improvement:.1f}个百分点 (相比贪心)")
            
            if improvement > 5:
                print(f"3. 🎉 显著提升! 证明动态expectimax有效")
                print(f"4. 建议: 基于{best['strategy']}策略进行深入优化")
            elif improvement > 0:
                print(f"3. ✅ 轻微提升，可以考虑实施")
            else:
                print(f"3. 🤔 提升有限，需要更多测试")
        else:
            print("1. 贪心策略仍然最佳，或测试时间不足")
    
    # 保存结果
    save_data = {
        'date': datetime.now().isoformat(),
        'total_time': time.time() - total_timeout.start_time,
        'program_fitness': program.fitness,
        'results': results
    }
    
    with open('timed_expectimax_results.json', 'w') as f:
        json.dump(save_data, f, indent=2)
    
    print(f"\n结果保存到 timed_expectimax_results.json")
    print(f"总耗时: {time.time() - total_timeout.start_time:.1f}秒")

if __name__ == "__main__":
    main()