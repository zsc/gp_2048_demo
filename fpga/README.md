# XCKU115 2048 搜索与多局比赛

本目录把仓库默认的 `simple_fast` evaluator（`NumEmptyCells + MaxTileValue`）和现有 node-budget 搜索语义实现为可综合 SystemVerilog。搜索分数使用 signed Q23.8。

## 多局队列架构

- 16384 个全局局号通过流式任务队列运行；FPGA 只保留 128 份活跃游戏上下文，完成一局就回收该槽位并启动下一局，避免上下文寄存器随总局数放大。
- 4 个独立搜索引擎，每个引擎 16 个 worker，共 64 个并行 worker。
- 每次只把 ready game 分配给空闲引擎；搜索结束后统一执行 move、随机放砖、更新统计并重新入队。
- 新砖严格为 90% 的 2、10% 的 4；空格选择采用 4-bit rejection sampling，保持均匀且不使用可变整数除法。
- 每局完成时写一条 128-bit summary；前 4 局额外保留完整逐步回放，其余局只保留步数、胜负、最高砖和最终盘面。
- USER1/JTAG 顺序读出 tournament header、16384 条摘要和回放页，随后生成自包含 HTML。

非 2 幂整数除法只出现在搜索期望值归一化：使用 Q24 reciprocal ROM 和 DSP 乘法。根节点 `/3` 使用常数 reciprocal；`/1`、`/2`、`/4` 是连线或移位。随机放砖不使用除法。

move 和 transpose 当前是 LUT 组合逻辑与连线，不占 BRAM，也没有 transposition table。给 64 个 worker 复制 65,536 项 row-move ROM 会受到 BRAM 容量和双口带宽限制，当前组合实现更适合吞吐优先的结构。

## OCaml budget 取样

`inference_cli.exe --simulate-games` 使用与 FPGA 相同的 32-bit LFSR、种子派生、90/10 放砖和均匀空格 rejection sampling，先用于选择硬件 budget，不使用 RTL 仿真。

| Node budget | 局数 | 达到 2048 | 平均步数 | OCaml 墙钟 |
|---:|---:|---:|---:|---:|
| 500 | 32 | 31.25% | 1,063.1 | 42.96 s |
| 1,000 | 16 | 75.00% | 1,467.4 | 76.91 s |
| 2,000 | 16 | 81.25% | 1,715.6 | 378.34 s |

500 对稳定完成 2048 不够；2,000 的 OCaml 计算量约为 1,000 的 4.9 倍，但样本胜率只增加 6.25 个百分点。因此当前 FPGA 选择 budget 1,000。

## Desk 工作流

本地只做源码编辑和轻量检查；综合、实现、编程和实板运行在 `ssh desk`。

先做 OCaml 完整对局取样：

```bash
opam exec --switch default -- dune build inference_cli.exe
_build/default/inference_cli.exe \
  --simulate-games 32 541638878 --node-budget 1000
```

直接生成 XCKU115 bitstream：

```bash
/tools/Xilinx/Vivado/2024.1/bin/vivado -mode batch \
  -source fpga/xcku115/build_queue.tcl \
  -tclargs 16384 4 16 1000 /tmp/gp_2048_queue_g16384
```

编程、运行、通过 JTAG 读回并生成 HTML：

```bash
./fpga/run_queue_board.sh \
  /tmp/gp_2048_queue_g16384/search_xcku115_queue_g16384_e4_w16.bit \
  /tmp/gp_2048_queue_g16384_capture
```

脚本默认等待 1,500,000 ms（25 分钟）后一次性读取 page 0..8192。按已测 128 局 8.898375 s 线性外推，16384 局纯计算约 1,139 s（18 分 59 秒）。若实板参数变化，可通过环境变量覆盖等待时间和末页：

```bash
TOURNAMENT_WAIT_MS=1800000 JTAG_LAST_PAGE=8192 \
  ./fpga/run_queue_board.sh BITSTREAM OUTPUT_DIR
```

页布局为：page 0 header，page 1..4096 为 16384 条摘要，page 4097..8192 为前 4 局回放。header 协议为 v2，局数、完成数和胜局数均为 16 bit。最终 HTML 会校验 16384 个连续局号、header 汇总、所有完成/终局/错误标志，以及前 4 局每一步的 move/spawn/终盘。

USER1/JTAG 的 XSDB 参数语义、bulk-sequence 模板、错页特征和验收方法见 [`xcku115/JTAG_READOUT_NOTES.zh-CN.md`](xcku115/JTAG_READOUT_NOTES.zh-CN.md)。

## 已有 128 局实板基线

XCKU115-FLVB2104-2-E、60 MHz、128 局、4×16 worker、node budget 1,000：

- 68/128 局达到 2048，实板胜率 53.125%。
- 最高砖分布：256×1、512×6、1024×53、2048×65、4096×3。
- 总计 167,434 步，平均 1,308.08 步。
- FPGA 比赛墙钟 533,902,525 cycles，即 8.898375 s。
- 吞吐 14.385 局/s、18,816 moves/s；4 个搜索引擎按累计 search cycles 计算的利用率为 97.96%。
- OCaml budget-1000 的 16 局样本约 4.81 s/局；按每局时间外推，FPGA 核心多局吞吐约快 69×。该数字比较的是比赛计算本身，不含 bitstream 编程和保守的全量 JTAG 导出等待。
- 128 条摘要全部 `done=1`、`game_over=1`，且 `invalid=0`、`overflow=0`、`replay_truncated=0`。
- 前 4 局共 4,853 条回放记录已逐步软件重算，每次 move、spawn、sequence 和最终盘面全部一致。

布局布线后使用 146,166 LUT、32,112 registers、210 DSP、64 RAMB36E2 + 4 RAMB18E2（66 个 BRAM36 tile 等价，3.06%）。190,865 条 routable nets 全部完成路由；setup/hold slack 为 1.023 ns / 0.029 ns。

最终产物：

- [`report/output/tournament_capture.txt`](report/output/tournament_capture.txt)：实板原始文本记录。
- [`report/output/tournament_report.html`](report/output/tournament_report.html)：可选择回放、前后/首尾跳转、进度条、0.25×–8× 自动播放、循环播放和键盘控制的自包含报告。

当前 evaluator 是固定的 `simple_fast`，不是从 JSON 动态加载任意 GP 指令数组。若需运行任意 evolved model，需要再加 evaluator microcode/parameter ROM；多局队列、并行搜索和 JTAG 报告层不依赖具体 evaluator 表达式。
