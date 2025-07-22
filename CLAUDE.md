本文档持续用中文更新。你和用户可以英语交流，但文档都用中文。

## 项目概述
这是一个结合 expectimax 搜索和遗传编程（GP）的 2048 游戏 AI。已成功将 Python 原型改写为高性能 OCaml 实现，获得 30-40 倍性能提升。

主要特性：
- Expectimax 搜索算法（支持节点限制和固定深度两种模式）
- 遗传编程自动进化评估函数
- 位操作优化的游戏引擎
- 查找表加速的评估函数
- Web 界面支持实时游戏和 AI 对战

## 实现计划

### 核心模块结构

1. **game.ml** - 游戏引擎
   - 使用 int64 表示棋盘（每4位表示一个格子的 log2(tile)）
   - 预计算查找表：左移、右移、得分、转置
   - 实现移动函数：move_left, move_right, move_up, move_down
   - 实现 add_random_tile（90% 概率为2，10% 概率为4）

2. **gp_tree.ml** - 遗传编程树
   - 节点类型：Add, Sub, Mul, SafeDiv, IfLTE, Constant, NumEmptyCells, MaxTileValue, MonotonicityScore, SmoothnessScore
   - 程序表示为前缀表达式列表
   - 实现递归求值函数

3. **expectimax.ml** - Expectimax 搜索
   - _gp_max_value：玩家回合，选择最大效用值
   - _gp_expect_value：计算机回合，计算期望值（考虑90%/10%的概率）
   - 深度限制和游戏结束检测

4. **gp_engine.ml** - 遗传算法
   - 种群管理（通常50-100个程序）
   - 锦标赛选择（默认大小5）
   - 子树交叉和变异操作
   - 适应度函数：fitness = avg_score + (avg_max_tile)²

5. **test_alignment.ml** - 对齐测试
   - 测试位操作的精确匹配
   - 测试浮点计算的误差范围
   - 使用固定随机种子验证结果一致性

### 关键优化
- 使用位操作优化棋盘操作
- 预计算所有可能的行操作（65536种）
- 并行化适应度评估（使用 Domainslib）

### 随机性控制
- 为初始棋盘和每步随机瓦片使用可注入的随机数生成器
- 支持固定种子以确保可重现性

## 当前实现状态

### 已完成模块
1. ✅ **game.ml** - 完整实现了游戏引擎
   - 位操作的棋盘表示
   - 预计算的查找表（init_tables 在模块加载时自动执行）
   - 四个方向的移动操作
   - 随机瓦片生成（使用可注入的 Random.State）
   - 评估函数：monotonicity_score, smoothness_score

2. ✅ **gp_tree.ml** - 完整实现了遗传编程树结构
   - 所有节点类型的定义
   - 程序求值函数
   - 随机树生成
   - 交叉和变异操作

3. ✅ **expectimax.ml** - 完整实现了 expectimax 算法
   - 递归的 MAX 和 EXPECT 节点求值
   - get_best_move 函数选择最佳移动
   - play_game 函数执行完整游戏
   - evaluate_fitness 函数计算适应度

4. ✅ **gp_engine.ml** - 完整实现了遗传算法引擎
   - 锦标赛选择
   - 种群进化（保留精英）
   - 适应度评估
   - run_evolution 主循环

5. ✅ **test_alignment.ml** - 创建了全面的测试套件
   - 位操作测试
   - 移动操作测试
   - 评估函数测试
   - GP树求值测试
   - 随机瓦片分布测试
   - Expectimax一致性测试

6. ✅ **main.ml** - 实现了命令行接口
   - 参数解析
   - 训练模式
   - 交互式游戏模式

### 构建系统
- 使用 dune 构建系统
- 创建了 dune-project 和 gp_2048.opam 文件
- 模块组织为 gp_2048_lib 库和 gp_2048 可执行文件

### 已验证的对齐
1. ✅ **基础位操作** - transpose、get_cell、set_cell 等位操作完全一致
2. ✅ **移动操作** - 使用 Python 生成的查找表（generate_tables.py），确保移动结果一致
3. ✅ **外部随机数注入** - 通过 random_tape.ml 实现确定性测试
4. ✅ **游戏逻辑** - 使用相同的随机序列时，游戏流程完全可重现
5. ✅ **Expectimax 算法** - expectimax_aligned.ml 实现了相同的搜索策略
6. ✅ **评估函数** - NumEmptyCells、MaxTileValue 等计算结果一致
7. ✅ **性能优化** - 在保持算法一致性的同时，实现 30-40 倍性能提升

### 待完成任务
1. ⏳ **并行化评估** - 已实现基于 Domainslib 的版本，但需要安装依赖
2. ✅ **修正 Expectimax 算法** - 已创建 expectimax_aligned.ml，与 Python 版本完全对齐

### 使用方法
```bash
# 生成查找表（必须先运行）
python generate_tables.py

# 编译
dune build

# 运行测试
dune test

# 训练
dune exec gp_2048 -- --generations 50 --pop-size 100 --seed 42

# 使用训练好的程序玩游戏
dune exec gp_2048 -- --play

# 运行 Web 界面
cd python && python app.py
# 然后访问 http://localhost:5050
```

### 注意事项
- OCaml 和 Python 的随机数生成器不同，需要通过外部注入随机数来实现确定性对比
- 使用 int64 类型存储棋盘状态，保证位操作的一致性
- 浮点运算（如评估函数）可能有微小差异，但不影响游戏决策

### 随机性控制
- 使用外部随机数序列（random_tape）来实现确定性测试
- 支持固定种子的内置随机数生成器用于正常游戏
- 通过相同的随机序列可以精确对比 Python 和 OCaml 实现

### 测试工具
1. **generate_random_tape.py** - 生成随机序列文件
2. **test_deterministic.ml/py** - 使用随机序列进行确定性游戏测试
3. **test_minimal.ml/py** - 最小化对齐测试
4. **test_alignment.ml** - OCaml 单元测试
5. **test_simple_alignment.py** - Python 基础操作对齐测试
6. **test_search_modes.py** - 测试节点预算和固定深度两种搜索模式
7. **test_num_empty_cells.ml** - 验证 NumEmptyCells 计算准确性

### Expectimax 算法差异
通过对比 app.py 中的 Python 实现和当前 OCaml 实现，发现关键差异：

1. **Python (app.py) 正确实现**：
   - `max_value`: 深度为 0 时返回评估值，否则调用 `expect_value(board, program, depth)`
   - `expect_value`: 计算期望值时调用 `max_value(board, program, depth-1)`
   - 深度在 expect → max 转换时递减

2. **OCaml (expectimax.ml) 当前实现**：
   - `gp_max_value`: 深度为 0 时返回评估值，否则调用 `gp_expect_value(board, program, depth)`
   - `gp_expect_value`: 计算期望值时调用 `gp_max_value(board, program, depth-1)`
   - 深度在 max → expect 转换时不变，在 expect → max 时才递减

这导致搜索深度实际上不同。已创建 `expectimax_aligned.ml` 作为修正版本，并通过测试验证与 Python 版本完全对齐。

### 新增文件
1. **expectimax_python.py** - 从 app.py 提取的纯 expectimax 实现
2. **expectimax_aligned.ml** - 与 Python 版本对齐的 OCaml 实现
3. **test_expectimax_aligned.py/ml** - 验证两个实现对齐的测试
4. **generate_tables.py** - 生成查找表的 Python 脚本，确保移动操作完全一致
5. **benchmark_comprehensive.py/ml** - 综合性能测试脚本

### 性能对比结果

通过 benchmark_comprehensive 测试，OCaml 实现相对 Python 的性能提升：

1. **棋盘操作**（移动）
   - Python: 450,347 moves/sec
   - OCaml: 85,120,325 moves/sec
   - **提升: 189倍**

2. **Expectimax 搜索**
   - 深度 1: **37倍**提升
   - 深度 2: **37倍**提升
   - 深度 3: **34倍**提升

3. **完整游戏**
   - 深度 1: **32倍**提升 (35.5 → 1,129 games/sec)
   - 深度 2: **36倍**提升 (0.4 → 15.7 games/sec)

4. **关键发现**
   - 两个实现使用相同策略时产生相似的游戏结果
   - OCaml 版本实现了 30-40 倍的整体性能提升
   - 位操作优化带来最大提升（189倍）
   - 查找表优化进一步提升评估函数性能（10.7倍）

### 实验结果

通过 experiment_ocaml_fast.ml 进行的实验显示：

1. **深度对比实验**
   - 深度 1: 平均分数 5,710，速度 474.5 games/sec
   - 深度 2: 平均分数 7,583，速度 6.1 games/sec
   - 深度 3: 平均分数 8,281，速度 0.1 games/sec
   - 更深的搜索带来更好的游戏表现，但计算开销急剧增加

2. **评估函数对比**
   - Simple (Empty + MaxTile): 平均分数 7,149
   - Weighted (2*Empty + MaxTile): 平均分数 7,626
   - Smoothness (Empty + MaxTile + Smoothness): 平均分数 7,998
   - 包含平滑度评分的函数表现最佳

3. **遗传编程进化**
   - 5代进化，种群大小20
   - 快速收敛到能达到256瓦片的程序
   - 最终进化程序平均分数 7,198（与手工设计程序相当）

4. **分数范围**
   - 单局最高分: 9,352（深度2）
   - 进化早期平均分: ~2,400
   - 成熟程序平均分: 7,000-8,000

### 动态深度和节点限制实验

通过 experiment_dynamic_depth.ml 和 experiment_node_limited.ml 的深入实验：

1. **节点限制策略对比**
   | 节点预算 | 平均分数 | 最高分数 | 速度 (games/sec) |
   |---------|---------|---------|-----------------|
   | 100     | 3,869   | 7,052   | 78.7           |
   | 500     | 6,492   | 11,876  | 23.9           |
   | 1,000   | 4,888   | 7,172   | 18.2           |
   | 5,000   | 4,196   | 10,508  | 5.1            |
   | 10,000  | 5,548   | 11,972  | 2.1            |
   | 50,000  | 4,786   | 6,604   | 0.5            |

2. **动态节点分配策略**
   - **基于分数的动态分配**（最佳）: 平均分数 8,788，速度 11.4 games/sec
   - **固定 5000 节点**: 平均分数 4,564，速度 4.6 games/sec
   - **线性空格数**: 平均分数 3,174，速度 11.9 games/sec
   - **指数衰减**: 平均分数 4,196，速度 9.6 games/sec
   - **综合策略**: 平均分数 5,181，速度 9.2 games/sec

3. **关键发现**
   - **最佳平衡点**: 500-1000 节点预算提供最佳的分数/速度权衡
   - **收益递减**: 超过 10k 节点后，性能反而下降
   - **动态分配胜出**: 基于分数的动态节点分配显著优于固定策略
   - **节点限制 vs 固定深度**: 节点限制搜索比固定深度更灵活
   - **极速模式**: 100 节点可达 78 games/sec，仍能获得 ~3,900 平均分

### 50 局游戏实验结果（6 核并行）

通过 50 局游戏的大样本实验，获得更可靠的性能数据：

| 节点预算 | 平均分数 | 最高分数 | 平均最大瓦片 | 速度 (games/sec) |
|---------|---------|---------|-------------|-----------------|
| 100     | 4,998±2,481 | 11,972 | 417 | 69.5 |
| 500     | 5,057±2,010 | 11,960 | 432 | 29.2 |
| 1,000   | 4,844±2,139 | 11,908 | 409 | 16.6 |
| 5,000   | 5,100±1,944 | 11,164 | 409 | 11.3 |
| 10,000  | 4,651±1,973 | 10,552 | 386 | 6.3  |
| 50,000  | 4,982±2,197 | 13,704 | 422 | 1.3  |

**关键发现**：
- 所有节点预算的平均分数相近（4,651-5,100），表明之前 10 局实验的方差过大
- 标准差很高（±1,944-2,481），显示游戏结果的高随机性
- 500-5,000 节点是性能和速度的最佳平衡点
- 基于分数的动态策略仍然最优（20 局平均 8,788，需要更多游戏验证）

### AI 性能排行榜

| 排名 | 策略 | 平均分数 | 最高分数 | 速度 (games/sec) | 备注 |
|-----|------|---------|---------|------------------|------|
| 🥇1 | 基于分数的动态节点 | 8,788 | 11,876 | 11.4 | 20 局，动态分配 |
| 🥈2 | 平滑度评估函数 | 7,998 | - | 3.9 | 10 局，深度 2 |
| 🥉3 | 固定深度 2 | 7,880 | - | 6.1 | 5 局，完整游戏 |
| 4 | 加权评估 | 7,626 | - | 5.6 | 10 局，2×空格 + 最大瓦片 |
| 5 | 固定深度 2 | 7,583 | 9,352 | 6.1 | 50 局游戏 |
| 6 | 进化最终 | 7,198 | - | - | 5 局，GP 进化 |
| 7 | 简单评估 | 7,149 | - | 5.9 | 10 局，空格 + 最大瓦片 |
| 8 | 节点预算 500 | 5,057±2,010 | 11,960 | 29.2 | 50 局，快速 |
| 9 | 节点预算 5000 | 5,100±1,944 | 11,164 | 11.3 | 50 局，平衡 |
| 10 | 固定深度 1 | 5,710 | - | 474.5 | 20 局，极速 |

### 最佳单局游戏
- **11,972** - 节点预算 10k
- **11,876** - 节点预算 500 / 基于分数的节点
- **11,160** - 基于分数的节点
- **10,508** - 节点预算 5k
- **9,352** - 固定深度 2

### 并行化实现

通过在 experiment_node_limited.ml 中添加多核支持：

1. **混合并行策略**
   - 默认使用 6 核（可通过命令行参数调整）
   - 只在工作量足够大时使用并行（每个移动 ≥1000 节点）
   - 小工作量使用顺序执行避免开销

2. **使用方法**
   ```bash
   # 默认：6 核，50 局游戏
   dune exec experiments/experiment_node_limited.exe
   
   # 指定核心数和游戏数
   dune exec experiments/experiment_node_limited.exe 6 100
   
   # 快速测试：6 核，10 局游戏
   dune exec experiments/experiment_node_limited.exe 6 10
   ```

3. **性能结果**（6 核 vs 单核）
   - 100 节点: 81.5 vs 78.7 games/sec（无需并行）
   - 1000 节点: 16.7 vs 18.2 games/sec（略有开销）
   - 5000 节点: 13.4 vs 5.1 games/sec（**2.6x 提升**）
   - 10000 节点: 5.6 vs 2.1 games/sec（**2.7x 提升**）
   - 50000 节点: 1.4 vs 0.5 games/sec（**2.8x 提升**）

4. **实现细节**
   - 使用 Task.parallel_for 并行评估移动
   - 游戏级并行化效果不佳（工作量不均匀）
   - 8 核性能反而下降（开销超过收益）

### 开发注意事项
- 优先修改现有文件而不是创建新文件
- 保持代码组织结构清晰
- 确保关键实验（如基于分数的动态节点）能正常运行
- 调试提示：可以使用 `llm -m gemini-2.0-flash 'describe' -a ~/image.jpg` 来读取截图内容

### 实用建议

1. **生产环境推荐配置**：
   - **极速模式**: 100 节点，70 games/sec，平均分 4,998±2,481
   - **快速模式**: 500 节点，29 games/sec，平均分 5,057±2,010
   - **平衡模式**: 5,000 节点，11 games/sec，平均分 5,100±1,944
   - **高质量模式**: 基于分数的动态分配，~10 games/sec，平均分 ~8,788（需验证）

2. **优化要点**：
   - 游戏结果方差很大，需要大样本（50+ 局）才能得出可靠结论
   - 固定节点预算在 100-50,000 范围内对平均分影响不大
   - 基于分数的动态节点分配可能是最优策略，但需要更多游戏验证
   - 6 核并行在大工作量时提供 2.5-2.8x 加速
   - **新增查找表优化**（2025-07-22）：
     - 为 monotonicity_score 和 smoothness_score 实现了查找表
     - 原理：预计算所有 65,536 种可能的行配置的分数
     - 内存使用：额外 512KB（每个表 256KB）
     - 性能提升：
       - 原始评估函数：10.7x 加速
       - 完整 GP 树评估：5.5x 加速
     - 实现文件：`lib/game_fast.ml`

### Web 界面优化（2025-07-22）

1. **完整游戏计算**
   - 添加了 `inference_cli.exe --play-game` 模式
   - OCaml 一次性计算完整游戏（通常 < 0.5 秒）
   - 返回包含所有步骤的 JSON 游戏轨迹

2. **高效回放系统**
   - Flask 后端调用 OCaml 一次获取完整游戏
   - Web 界面按用户设定速度回放游戏轨迹
   - 可调节回放速度（50-1000ms/步）

3. **性能提升**
   - 原方案：每步调用 OCaml，产生数百次进程开销
   - 新方案：一次调用，纯前端回放
   - 计算时间：< 50ms（Flask 调用）
   - 游戏完成时间：仅受回放速度限制

4. **使用体验**
   - 选择模型，点击"Let AI Play"
   - 立即开始游戏回放（计算已完成）
   - 可随时调整回放速度
   - 显示总计算时间和节点预算

### Web 界面功能

1. **双搜索模式支持**（2025-07-22）
   - **节点预算模式**：限制搜索节点总数（100-2000）
   - **固定深度模式**：固定搜索深度（1-5）
   - 两种模式通过下拉菜单切换
   - 后端自动识别并使用相应算法

2. **模型选择**
   - 下拉菜单显示所有可用模型
   - 支持刷新模型列表
   - 当前有 10 个预训练模型可选

3. **游戏控制**
   - New Game：开始新游戏
   - Let AI Play：AI 自动完成整局游戏
   - 可调节回放速度（50-1000ms/步）

4. **性能显示**
   - 实时显示推理时间
   - 显示使用的节点预算或搜索深度
   - 游戏分数和最大瓦片实时更新

### 最新更新（2025-07-22 下午）

1. **双搜索模式实现**
   - 添加了节点预算和固定深度两种搜索模式
   - Web 界面支持模式切换和参数调整
   - OCaml 后端（inference_cli.ml）支持两种模式
   - 通过 test_search_modes.py 验证功能正常

2. **NumEmptyCells 准确性验证**
   - 创建 test_num_empty_cells.ml 进行全面测试
   - 测试空棋盘、满棋盘、随机棋盘等多种情况
   - 验证计算 100% 准确

3. **Web 界面调试**
   - 使用 Selenium 截图功能调试下拉框问题
   - 确认模型下拉框正常工作，显示所有 10 个模型
   - 添加了 Selenium 截图调试技巧到开发注意事项

### 当前工作进度（2025-07-22）

1. **已完成的优化**
   - ✅ 添加 `--play-game` 标志到 inference_cli.ml
   - ✅ 实现完整游戏轨迹生成（JSON 格式）
   - ✅ 更新 Flask app 添加 `request_complete_game` 和 `api/play_complete_game` 端点
   - ✅ 修改前端添加游戏回放功能
   - ✅ 添加可调节的回放速度控制（50-1000ms）
   - ✅ 验证 OCaml 后端可以在 < 0.5 秒内生成完整游戏
   - ✅ 验证 Flask API 端点正常工作

2. **待完成任务**
   - ✅ **Web 界面端到端测试**
     - 已成功验证 AI 完整游戏流程
     - 游戏可以从开始玩到结束（测试得分 5420）
     - 需要优化测试脚本处理游戏结束提示
   - ✅ **验证游戏动画完整播放**
     - 确认前端正确处理 `complete_game_result` 事件
     - `replayGame()` 函数正常工作，游戏回放流畅
   - ⏳ **测试不同模型的表现**
     - simple_fast.json (500 节点) - 已测试，得分 5420
     - balanced_best.json (5000 节点) - 待测试
     - high_performance.json (1000 节点) - 待测试

3. **解决的问题**
   - ✅ 移除了 Train 标签页，简化界面
   - ✅ 修复了初始游戏状态（isGameOver 初始值）
   - ✅ 使用 JavaScript 执行解决了下拉框交互问题
   - ✅ 游戏成功完成并显示最终分数
   - ✅ **修复了 New Game 按钮问题**（2025-07-22）
     - 问题：`Game2048.new_game()` 方法不存在
     - 解决：改用正确的 `Game2048.reset_board()` 方法
     - 结果：棋盘正确初始化，显示 2 个初始瓦片
   - ✅ **验证模型下拉框正常工作**（2025-07-22）
     - 使用 Selenium 截图功能确认
     - 所有 10 个模型正确显示
     - 选择功能正常

4. **验证结果**
   - **成功运行完整游戏**：AI 使用 simple_fast.json 模型完成游戏
   - **最终得分**：多次测试得分 1404、5420、6124、11380 分
   - **最大方块**：达到 512-1024
   - **游戏时长**：约 20-30 秒完成整局游戏（使用 20ms 播放速度）
   - **回放速度**：测试时使用 20ms/步，默认 200ms/步
   - **完整流程**：从模型选择 → 开始游戏 → AI 自动播放 → 游戏结束提示
   - **New Game 修复后**：棋盘正确初始化，boardInt='17'，显示 2 个瓦片
   
5. **技术细节**
   - Web 界面使用 Socket.IO 实时通信
   - OCaml 后端一次性计算完整游戏轨迹（< 0.5 秒）
   - 前端按设定速度回放游戏，无需多次调用后端
   - 测试脚本使用 Selenium WebDriver 自动化浏览器操作

## 项目文件结构

### 核心 OCaml 库 (`lib/`)
- **game.ml** - 游戏引擎核心实现（位操作、移动、评分）
- **game_fast.ml** - 带查找表优化的游戏引擎（10.7x 性能提升）
- **gp_tree.ml** - 遗传编程树结构和操作
- **gp_tree_json.ml** - GP 树的 JSON 序列化/反序列化
- **gp_engine.ml** - 遗传算法引擎（选择、交叉、变异、进化）
- **expectimax_aligned.ml** - 与 Python 对齐的 expectimax 算法
- **expectimax_memoized.ml** - 带记忆化的 expectimax（实验性）
- **random_tape.ml** - 外部随机数注入（用于对齐测试）

### 主程序
- **main.ml** - 命令行界面，支持训练和交互式游戏
- **inference_cli.ml** - 推理命令行工具，支持单步和完整游戏

### 实验脚本 (`experiments/`)
- **experiment_ocaml_fast.ml** - 基础性能和评估函数对比实验
- **experiment_node_limited.ml** - 节点限制策略实验（支持多核并行）
- **experiment_dynamic_depth.ml** - 动态深度分配策略实验
- **gp_evolution_fast.ml** - 快速 GP 进化（使用所有优化）
- **gp_evolution_leaderboard.ml** - 带排行榜的 GP 进化

### 基准测试 (`benchmarks/`)
- **benchmark_comprehensive.ml/py** - 综合性能对比（OCaml vs Python）
- **benchmark_comparison.ml/py** - 基础操作对比测试
- **benchmark_eval_lut.ml** - 查找表性能测试

### Python 实现 (`python/`)
- **game.py** - Python 版游戏引擎（金标准）
- **gp_engine.py** - Python 版遗传编程引擎
- **expectimax_python.py** - Python 版 expectimax 算法
- **app.py** - Flask Web 应用后端
- **generate_tables.py** - 生成移动操作查找表
- **generate_random_tape.py** - 生成随机序列文件
- **templates/index.html** - Web 界面前端

### 模型文件 (`python/models/`)
- **simple_fast.json** - 简单快速模型（500 节点，平均 5057 分）
- **balanced_best.json** - 平衡模型（5000 节点，包含平滑度）
- **high_performance.json** - 高性能模型（1000 节点）

### 测试脚本
- **test_web_complete_game.py** - Web 界面端到端测试
- **test_single_game.py** - 单局游戏测试
- **verify_integration.py** - 集成验证测试

### 文档和结果
- **README.md** - 项目说明
- **CLAUDE.md** - 开发文档和进度跟踪（本文档）
- **results/leaderboard.md** - AI 性能排行榜
- **node_limited_results_50games.txt** - 50 局游戏实验结果

### 构建配置
- **dune-project** - Dune 项目配置
- **dune** - 根目录构建配置
- **lib/dune** - 库构建配置
- **experiments/dune** - 实验脚本构建配置

### 关键目录说明
- `lib/` - 所有核心算法和数据结构
- `experiments/` - 各种实验和性能测试
- `benchmarks/` - 性能基准测试
- `python/` - Python 参考实现和 Web 界面
- `results/` - 实验结果和排行榜
- `tests/` - 测试数据和脚本

## 模型评估结果（2025-07-22）

使用 50 局游戏评估了现有的 3 个模型：

### 模型排行榜

| 排名 | 模型 | 平均分数 | 最高分数 | 平均最大瓦片 | 最高瓦片 | 节点预算 | 描述 |
|------|------|---------|---------|-------------|---------|---------|------|
| 🥇 1 | simple_fast.json | 7,356 | 9,368 | 620 | 1024 | 500 | 简单快速模型 |
| 🥈 2 | high_performance.json | 7,165 | 9,364 | 543 | 1024 | 1000 | 高性能模型 |
| 🥉 3 | balanced_best.json | 2,594 | 7,116 | 204 | 512 | 5000 | 平衡模型（包含平滑度） |

### 关键发现

1. **simple_fast 表现最佳**
   - 使用最简单的评估函数：`Add(NumEmptyCells, MaxTileValue)`
   - 仅 500 节点预算却达到最高平均分数
   - 证明了简单策略的有效性

2. **节点预算与性能不成正比**
   - balanced_best 使用 5000 节点但表现最差
   - 可能是因为包含了 MonotonicityScore 和 SmoothnessScore 导致过度优化

3. **性能指标**
   - 所有模型评估速度约 6-7 games/sec
   - 两个模型达到了 1024 瓦片
   - 分数范围很大，显示游戏的高随机性

### 更新：移动限制对性能的影响（2025-07-22）

通过 `test_simple_fast_nodes.ml` 实验，发现之前的评估可能低估了模型性能：

1. **无移动限制时的真实性能**（max_moves = 1,000,000）
   - 100 节点: 15,263 平均分（10.1 games/sec）
   - 500 节点: 21,557 平均分（2.0 games/sec）
   - 1000 节点: 24,789 平均分（0.7 games/sec）
   - 1500 节点: 26,593 平均分（0.3 games/sec）- **最优配置**
   - 2000 节点: 24,654 平均分（0.2 games/sec）- 收益递减
   - 所有配置都能达到 2048 瓦片

2. **性能差异分析**
   - 之前报告的 7,356 分可能是由于人为的移动限制
   - 无限制时，simple_fast 性能提升 ~2.9-3.6 倍
   - 1500 节点是性能最优点（26,593 分），之后收益递减
   - max_moves 从 10,000 增加到 1,000,000 对结果影响很小，说明游戏通常在 10,000 步内结束

3. **速度与质量权衡**
   - 100 节点比 1500 节点快 33 倍
   - 1500 节点比 100 节点得分高 74%
   - 最佳性能：1500 节点
   - 最佳平衡点：500-1000 节点（速度与性能的折中）

### 训练和进化进展

1. **已完成的工作**
   - ✅ 修改了 `gp_evolution_fast.ml` 支持命令行参数
   - ✅ 创建了 `train_models.ml` 用于批量训练
   - ✅ 创建了 `evaluate_models.ml` 用于模型评估
   - ✅ 生成了查找表以支持快速游戏引擎
   - ✅ 创建了 `beat_simple_fast.ml` 进化实验
   - ✅ 实现了 6 核并行评估加速

2. **进化实验成果**（beat_simple_fast）
   - **champion_gen15.json**: 成功超越 simple_fast
     - 平均分数: 7,528.60（超越 simple_fast 172.60 分）
     - 最高分数: 9,292
     - 平均最大瓦片: 589
     - 程序结构: `((NumEmptyCells + (NumEmptyCells + MaxTileValue)) + (MaxTileValue × (((MaxTileValue × 2.0) + NumEmptyCells) + (MaxTileValue × 2.0))))`
   - 使用种群大小 60，精英保留 10，锦标赛选择大小 7
   - 每 5 代保存检查点，20 局游戏彻底评估

3. **关键改进**
   - 将 simple_fast 加入初始种群确保良好起点
   - 增加游戏数从 3 到 10 提高评估可靠性
   - 设置 max_moves = 10000 允许游戏玩到结束
   - 使用 6 核并行评估，速度提升 ~6 倍

### simple_fast 评估函数测试结果

`Add(NumEmptyCells, MaxTileValue)` 是最简单有效的评估函数，在不同配置下的表现：

1. **固定深度 10，不同节点预算**（max_moves = 1,000,000）
   - 100 节点: 15,263 平均分（10.1 games/sec）
   - 500 节点: 21,557 平均分（2.0 games/sec）
   - 1000 节点: 24,789 平均分（0.7 games/sec）
   - 1500 节点: 26,593 平均分（0.3 games/sec）- **最优**
   - 2000 节点: 24,654 平均分（0.2 games/sec）

2. **动态深度 (12/8/4/4)，不同节点预算**
   - 100 节点: 20,964 平均分（16.3 games/sec）- 比固定深度提升 37%
   - 500 节点: 23,729 平均分（2.7 games/sec）- 比固定深度提升 10%
   - 1000 节点: 20,050 平均分（1.4 games/sec）
   - 1500 节点: 19,751 平均分（0.9 games/sec）
   - 2000 节点: 19,035 平均分（0.6 games/sec）

### 动态深度实验（2025-07-22）

通过修改 `test_simple_fast_nodes.ml` 支持动态深度搜索，进行了详细的消融研究：

1. **动态深度 vs 固定深度对比**
   - 100 节点：动态 20,964 vs 固定 15,263（+37%）
   - 500 节点：动态 23,729 vs 固定 21,557（+10%）
   - 1000 节点：动态 20,050 vs 固定 24,789（-19%）
   - 低节点预算时动态深度明显优于固定深度

2. **动态深度参数消融研究**（1000 节点）
   | 配置 | 阈值 (t1/t2/t3/max) | 平均分数 | 速度 (games/sec) |
   |------|---------------------|---------|-----------------|
   | Early switch | 14/8/4/4 | **22,358** | 1.7 | ← 最佳
   | Late switch | 10/8/4/4 | 21,948 | 1.5 |
   | Deep early | 12/8/6/4 | 21,907 | 1.0 |
   | Mid late | 12/6/4/4 | 21,657 | 2.0 |
   | Conservative | 10/6/2/5 | 20,113 | 3.2 | ← 最快
   | Baseline | 12/8/4/4 | 17,515 | 2.2 |

3. **关键发现**
   - 早期切换（14 个空格时用深度 1）效果最好
   - 基线配置（12/8/4/4）并非最优
   - 切换阈值比最大深度更重要
   - 保守策略速度最快且性能尚可

4. **动态深度策略**
   ```ocaml
   let get_dynamic_depth (t1, t2, t3, max_depth) empty_cells =
     if empty_cells >= t1 then 1
     else if empty_cells >= t2 then 2
     else if empty_cells >= t3 then 3
     else max_depth
   ```

### 评估函数性能对比总结

1. **simple_fast**: `Add(NumEmptyCells, MaxTileValue)`
   - 最佳配置：1500 节点，固定深度 10 → **26,593 平均分**
   - 简单高效，是所有复杂策略的基准

2. **champion_gen15**: 进化得到的复杂函数
   - 结构：`((NumEmptyCells + (NumEmptyCells + MaxTileValue)) + (MaxTileValue × ...))`
   - 在限制条件下（较少游戏数）达到 7,529 平均分
   - 需要在相同条件下重新评估以公平对比

3. **动态深度优化后的 simple_fast**
   - 最佳配置：500 节点，动态深度 (14/8/4/4) → **23,729 平均分**
   - 在计算资源受限时表现优异

```ocaml
(* lib/game_fast.mli *)
type board = int64
val empty_board : int64
val row_mask : int64
val cell_mask : int64
val get_row : int64 -> int -> int64
val set_row : int64 -> int -> int64 -> int64
val get_cell : int64 -> int -> int
val set_cell : int64 -> int -> int -> int64
val left_table : int array
val right_table : int array
val score_table : int array
val monotonicity_table : float array
val smoothness_table : float array
val load_table_from_file : string -> int array
val compute_row_monotonicity : int -> float
val compute_row_smoothness : int -> float
val init_tables : unit -> unit
val transpose : int64 -> int64
val move_left : int64 -> int64
val move_right : int64 -> int64
val move_up : int64 -> int64
val move_down : int64 -> int64
val get_score_for_move : int64 -> [< `Down | `Left | `Right | `Up ] -> int
val count_empty_cells : int64 -> int
val get_empty_cells : int64 -> int list
val add_random_tile : int64 -> Random.State.t -> int64
val get_max_tile : int64 -> int
val is_game_over : Int64.t -> bool
val monotonicity_score : int64 -> float
val smoothness_score : int64 -> float
(* lib/game.mli *)
type board = int64
val empty_board : int64
val row_mask : int64
val cell_mask : int64
val get_row : int64 -> int -> int64
val set_row : int64 -> int -> int64 -> int64
val get_cell : int64 -> int -> int
val set_cell : int64 -> int -> int -> int64
val left_table : int array
val right_table : int array
val score_table : int array
val load_table_from_file : string -> int array
val init_tables : unit -> unit
val transpose : int64 -> int64
val move_left : int64 -> int64
val move_right : int64 -> int64
val move_up : int64 -> int64
val move_down : int64 -> int64
val get_score_for_move : int64 -> [< `Down | `Left | `Right | `Up ] -> int
val count_empty_cells : int64 -> int
val get_empty_cells : int64 -> int list
val add_random_tile : int64 -> Random.State.t -> int64
val get_max_tile : int64 -> int
val is_game_over : Int64.t -> bool
val monotonicity_score : int64 -> float
val smoothness_score : int64 -> float
(* lib/gp_tree.mli *)
type node =
    Add
  | Sub
  | Mul
  | SafeDiv
  | IfLTE
  | Constant of float
  | NumEmptyCells
  | MaxTileValue
  | MonotonicityScore
  | SmoothnessScore
type program = {
  nodes : node array;
  mutable fitness : float;
  mutable games_played : int;
  mutable avg_score : float;
  mutable avg_max_tile : float;
}
val node_arity : node -> int
val is_terminal : node -> bool
val safe_div : float -> float -> float
val eval_program : program -> int64 -> float
val eval : program -> int64 -> float
val random_terminal : Random.State.t -> node
val random_function : Random.State.t -> node
val random_tree : Random.State.t -> int -> node list
val create_random_program : Random.State.t -> int -> program
val copy_program : program -> program
val count_nodes_from : int -> node array -> int
val extract_subtree : node array -> int -> node array
val crossover : Random.State.t -> program -> program -> program * program
val mutate : Random.State.t -> program -> float -> int -> program
val program_to_string : program -> string
(* lib/random_tape.mli *)
type random_event = { position : int; value : int; }
type random_tape = { events : random_event array; mutable index : int; }
val load_random_tape : string -> random_tape
val save_random_tape : string -> random_tape -> unit
val get_next_event : random_tape -> random_event
val reset_tape : random_tape -> unit
val create_empty_tape : unit -> random_tape
val record_event : random_tape -> int -> int -> random_tape
val add_random_tile_from_tape : int64 -> random_tape -> int64
val add_tile_with_event : int64 -> random_event -> int64
```
