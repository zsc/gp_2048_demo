# XCKU115 USER1/JTAG 批量读出经验

本文记录 2048 多局队列在 XCKU115 上通过 `BSCANE2/USER1` 读回统计和回放时遇到的问题、根因与已验证做法。重点是 XSDB 的 sequence 语义、跨时钟页流，以及如何区分“搜索计算错误”和“JTAG 读页错位”。

## 最终采用的读出结构

- FPGA 游戏时钟为 60 MHz，JTAG 使用 `BSCANE2` 的 USER1 链。
- page 0 是 tournament header。
- 16384 局配置中，page 1..4096 是摘要，每页 4 条、每条 128 bit。
- page 4097 起是回放区。每局预留 1024 页，每页 4 条 128-bit 记录；当前只保留前 4 局，因此末页为 8192。
- 比赛完成前页流保持在 page 0。完成后，非零 TDI 的 DR scan 才使页号加一。
- 主机先 capture header，再做一次只用于推进的 scan，之后 page `p` 对应 capture 列表中的 `p + 1` 项。
- 所有摘要在游戏结束时写入独立 summary BRAM；JTAG 不直接扇出读取活跃游戏上下文。

相关实现：

- `search_jtag_pages.sv`：USER1 shift register、页计数和跨时钟同步。
- `search_xcku115_queue_top.sv`：header 和页地址空间。
- `read_queue.tcl`：XSDB bulk sequence、capture 解码和文本导出。
- `game2048_tournament_queue.sv`：摘要与回放 BRAM。

## XSDB 参数最容易误解的地方

### `-tdi` 不是“移入这个整数”

XSDB 对 sequence shift 的定义是：

- `-tdi 0`：整个 SHIFT 阶段每个时钟都移入 0。
- `-tdi 1`：整个 SHIFT 阶段每个时钟都移入 1。
- 若要移入一个整数，必须使用 `-integer bits data` 形式；LSB 先移入。

因此下面写法已经会连续移入 512 个 1，不需要构造 512-bit 大整数：

```tcl
$seq drshift -state IDLE -tdi 1 -capture 512
```

早期曾把 `-tdi $page` 当作 512-bit 页地址命令使用。这会把非零页号退化成“全 1”，无法表达任意页地址；由此看到的 header 正常、摘要错位，并不是 FPGA 搜索结果坏了。

### 每次 shift 都显式指定 `-state IDLE`

sequence shift 的默认结束状态是 `RESET`。读 USER1 时如果漏掉 `-state IDLE`，TAP 会复位，`BSCANE2.RESET` 也可能清掉页流状态。

正确形式：

```tcl
$seq irshift -state IDLE -integer 12 0x0A4
$seq drshift -state IDLE -tdi 0 -capture 512
```

### 不要每页单独创建一次完整 sequence

曾尝试为每页重复执行：创建 sequence、IRSHIFT USER1、DRSHIFT、run、delete。短页段看似可读，但从摘要切换到回放以及跨过回放预留空洞后，页状态和数据流水会错位。

已验证的稳定办法是：

1. 一次 IRSHIFT 选择 USER1。
2. 在同一个 sequence 中加入所有 DRSHIFT。
3. 一次 `run -bits` 拉回整个 capture 列表。

已验证的 128 局配置一次 capture page 0..4128，数据量约 2.1 Mbit。16384 局的 v2 页空间为 page 0..8192，约 4.2 Mbit，仍采用同一个 bulk sequence，不能拆成逐页 sequence。

## 已验证的 bulk sequence 模式

128 局已验证模板如下；16384 局把等待改为 1,500,000 ms、`last_page` 改为 8192：

```tcl
after 1500000

set last_page 8192
set seq [jtag sequence]
$seq irshift -state IDLE -integer 12 0x0A4

# capture header，保持 page 0
$seq drshift -state IDLE -tdi 0 -capture 512

# 再 capture 一次 header，并在 UPDATE 后推进到 page 1
$seq drshift -state IDLE -tdi 1 -capture 512

# 依次 capture page 1..last_page；每次结束后推进一页
for {set page 1} {$page <= $last_page} {incr page} {
  $seq drshift -state IDLE -tdi 1 -capture 512
}

set captures [$seq run -bits]
$seq delete

# page p 位于 captures[p + 1]；captures[0] 是第一次 header。
```

默认等待 25 分钟来自 128 局实测 8.898375 秒的线性外推（16384 局约 18 分 59 秒）再加余量。若以后 budget 或 evaluator 可动态变化，应增加明确的“重新定位 page 0 / 启动流”握手，避免依赖固定等待。

## 跨时钟和 BRAM 延迟

- 页计数发生在 JTAG UPDATE 域，经两级寄存器同步到 60 MHz 游戏域。
- summary/replay BRAM 是同步读，之后还有一次 512-bit capture 寄存。
- 单次 512-bit JTAG scan 远长于这些 60 MHz 流水延迟，因此连续 scan 之间无需额外毫秒级等待。
- 但首个 scan 不能同时承担“改地址”和“读取新地址”：先推进，再在下一次 scan capture 新页。

## 如何快速判断故障在哪一层

### header 正确且 `completed=games`

说明时钟、配置、搜索队列和全局计数基本正常。此次第一次实板运行已经得到：

```text
completed=128
wins_2048=68
total_moves=167434
total_search_cycles=2092111647
wall_cycles=533902525
```

如果这时 GAME/RECORD 内容为零或像 header，优先检查页寻址、scan 顺序和同步读延迟，不要先怀疑搜索核心。

### 摘要正确、回放像随机终盘

此次错误数据其实是旧摘要页被当成 replay record 解释：

- `move` 会出现 4..7；
- `spawn_cell` 会超过 15；
- `sequence` 大多为 0；
- board 看起来像填满的终盘。

这是非常典型的页流错位特征，不是回放 BRAM 写坏。

### 最终验收条件

- 全部 GAME 都满足 `done=1`、`game_over=1`，局号从 0 连续到 `games-1`。
- `invalid=0`、`overflow=0`、`replay_truncated=0`。
- 每个回放的 record 0 必须为 `move=7`，且初始棋盘恰有两个砖。
- 后续 `record.index == record.sequence`。
- 每一步在软件中重新执行 move，再按 `spawn_cell/spawn_value` 放砖，必须得到记录棋盘。
- 回放记录数必须等于 `moves + 1`。
- 回放最后棋盘必须等于该局摘要的 `final_board`。

`generate_queue_report.py` 会执行上述逐步重算；只有全部通过才生成 HTML。最终实板 capture 中 4 局共 4,853 条记录已全部通过。

## BRAM 使用结论

128 局基线布局后使用：

- 64 个 RAMB36E2；
- 4 个 RAMB18E2；
- 合计 66 个 BRAM36 tile 等价，占 XCKU115 的 3.06%。

其中回放存储占 56 个 RAMB36E2 + 4 个 RAMB18E2；128 局时，4 个 128-bit 并行 summary bank 额外占 8 个 RAMB36E2。16384 局摘要有效数据约 2 Mbit，预计约增加 57 个 BRAM36 容量级别，仍远低于 XCKU115 总量；最终以实现报告为准。

16384 局不能把活跃上下文数组直接放大 128 倍，否则寄存器和选择网络会失控。当前实现固定 128 个活跃槽位，槽位完成后写全局 summary BRAM，再绑定下一个全局局号。由此总局数主要影响摘要 BRAM 深度和运行时间，不复制 64-worker 搜索核心。

move 逻辑和 transpose 当前均为 LUT/连线，未使用 BRAM move ROM；也没有 transposition table。把 65,536 项行 move 表复制到 64 个 worker 会消耗过多 BRAM 端口与容量，不能只看一份 ROM 的大小。

## 后续协议改进建议

- 在每页加入 page number 和小型 CRC，主机可立即发现错页，而不是等到 replay 校验失败。
- 增加显式 `rewind/start-stream` 命令，使同一 bitstream 可重复读出，并支持动态完成时间。
- 回放页改成紧凑连续布局，或在 header 中给出每局起始页，避免扫描每局固定 1024 页造成的空洞。
- 若保留随机页访问，地址命令应使用明确的 `-integer 512 data` 编码，并在硬件侧回显所选页号；不要依赖未验证的 TDI 位序假设。
