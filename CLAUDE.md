本文档持续用中文更新。你和用户可以英语交流，但文档都用中文。
这是一个 expectimax + genetic programming 的程序。
我们希望改写成 ocaml 版本来实现加速。改写要以 python 版为金标准来保证对齐（纯整数计算要 bit 对齐，float 要在误差范围内）。
注意有两个随机来源：一个是开局局面，一个是每一轮的 random tile（这个应该用一套共同的随机数来注入来消除随机性）。

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
1. ✅ **基础位操作** - transpose、get_cell、set_cell 等完全对齐
2. ✅ **移动操作** - move_left、move_right、move_up、move_down 完全对齐
3. ✅ **外部随机数注入** - 实现了 random_tape.ml 和相应的 Python 代码
4. ✅ **确定性游戏测试** - 使用相同的随机序列，基础游戏机制完全对齐

### 待完成任务
1. ⏳ **并行化评估** - 已实现基于 Domainslib 的版本，但需要安装依赖
2. ✅ **修正 Expectimax 算法** - 已创建 expectimax_aligned.ml，与 Python 版本完全对齐

### 使用方法
```bash
# 编译
dune build

# 运行测试
dune test

# 训练
dune exec gp_2048 -- --generations 50 --pop-size 100 --seed 42

# 使用训练好的程序玩游戏
dune exec gp_2048 -- --play
```

### 注意事项
- 随机数生成器使用 OCaml 的 Random.State，可以通过种子控制。但与 Python 不同，所以不能完全对齐。完全对齐要靠外部注入随机数。
- 所有整数运算使用 int64 确保与 Python 版本位级别对齐
- 浮点运算可能有微小差异，但在可接受范围内

### 随机性对齐方案
为了确保 Python 和 OCaml 版本的完全对齐，需要消除两个随机源的差异：

1. **初始棋盘随机性** - 游戏开始时的两个随机瓦片位置
2. **游戏过程随机性** - 每步移动后添加的随机瓦片（位置和值）

方案：使用外部随机数序列文件，格式如下：
```
# random_sequence.txt
# 每行表示一个随机事件：tile_position tile_value(1=2, 2=4)
0 1   # 第一个瓦片在位置0，值为2
5 1   # 第二个瓦片在位置5，值为2
3 2   # 第三个瓦片在位置3，值为4
...
```

这样可以确保：
- Python 和 OCaml 使用完全相同的随机序列
- 游戏过程完全可重现
- 能够精确对比两个实现的行为差异

### 测试工具
1. **generate_random_tape.py** - 生成随机序列文件
2. **test_deterministic.ml/py** - 使用随机序列进行确定性游戏测试
3. **test_minimal.ml/py** - 最小化对齐测试
4. **test_alignment.ml** - OCaml 单元测试
5. **test_simple_alignment.py** - Python 基础操作对齐测试

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
