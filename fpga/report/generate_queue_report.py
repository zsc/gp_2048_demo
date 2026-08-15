#!/usr/bin/env python3
"""Generate a self-contained interactive HTML report from read_queue.tcl."""

from __future__ import annotations

import argparse
import json
from pathlib import Path


DIRECTIONS = ["↑", "↓", "←", "→"]
DIRECTION_NAMES = ["上", "下", "左", "右"]


def parse_fields(line: str) -> tuple[str, dict[str, str]]:
    parts = line.strip().split()
    if not parts:
        return "", {}
    fields: dict[str, str] = {}
    for part in parts[1:]:
        if "=" in part:
            key, value = part.split("=", 1)
            fields[key] = value
    return parts[0], fields


HEX_FIELDS = {"magic", "base_seed", "final_board", "board", "engine_busy"}


def as_int(key: str, value: str) -> int:
    if key in HEX_FIELDS or any(character in value.lower() for character in "abcdef"):
        return int(value, 16)
    return int(value, 10)


def parse_capture(path: Path) -> tuple[dict, list[dict], dict[int, list[dict]]]:
    tournament: dict = {}
    games: list[dict] = []
    replays: dict[int, list[dict]] = {}
    for line_number, line in enumerate(path.read_text().splitlines(), 1):
        kind, fields = parse_fields(line)
        if not kind:
            continue
        if kind == "TOURNAMENT":
            tournament = {key: as_int(key, value) for key, value in fields.items()}
        elif kind == "GAME":
            game = {key: as_int(key, value) for key, value in fields.items()}
            games.append(game)
        elif kind == "RECORD":
            record = {key: as_int(key, value) for key, value in fields.items()}
            replays.setdefault(record["game"], []).append(record)
        else:
            raise ValueError(f"{path}:{line_number}: unknown record {kind!r}")
    if not tournament:
        raise ValueError("capture has no TOURNAMENT header")
    games.sort(key=lambda item: item["game"])
    for records in replays.values():
        records.sort(key=lambda item: item["index"])
    return tournament, games, replays


def board_exponents(board: int) -> list[int]:
    return [(board >> (cell * 4)) & 0xF for cell in range(16)]


def merge_line(values: list[int]) -> tuple[list[int], int]:
    compact = [value for value in values if value]
    merged: list[int] = []
    score = 0
    index = 0
    while index < len(compact):
        if index + 1 < len(compact) and compact[index] == compact[index + 1]:
            exponent = compact[index] + 1
            merged.append(exponent)
            score += 1 << exponent
            index += 2
        else:
            merged.append(compact[index])
            index += 1
    return merged + [0] * (4 - len(merged)), score


def move_board(cells: list[int], direction: int) -> tuple[list[int], int]:
    result = [0] * 16
    score = 0
    if direction in (2, 3):
        for row in range(4):
            indices = [row * 4 + column for column in range(4)]
            if direction == 3:
                indices.reverse()
            merged, line_score = merge_line([cells[index] for index in indices])
            score += line_score
            for index, value in zip(indices, merged):
                result[index] = value
    else:
        for column in range(4):
            indices = [row * 4 + column for row in range(4)]
            if direction == 1:
                indices.reverse()
            merged, line_score = merge_line([cells[index] for index in indices])
            score += line_score
            for index, value in zip(indices, merged):
                result[index] = value
    return result, score


def cells_to_board(cells: list[int]) -> int:
    board = 0
    for index, exponent in enumerate(cells):
        board |= exponent << (index * 4)
    return board


def prepare_replays(games: list[dict], replays: dict[int, list[dict]]) -> list[dict]:
    game_by_id = {game["game"]: game for game in games}
    prepared: list[dict] = []
    for game_id, records in sorted(replays.items()):
        if not records:
            continue
        if records[0]["index"] != 0 or records[0]["move"] != 7:
            raise ValueError(f"game {game_id}: missing initial replay record")
        previous = board_exponents(records[0]["board"])
        if sum(value != 0 for value in previous) != 2:
            raise ValueError(f"game {game_id}: initial board does not contain two tiles")
        cumulative_score = 0
        timeline = []
        for position, record in enumerate(records):
            board = board_exponents(record["board"])
            score_delta = 0
            if position:
                if record["index"] != position or record["sequence"] != position:
                    raise ValueError(f"game {game_id}: replay sequence breaks at {position}")
                direction = record["move"]
                if direction not in range(4):
                    raise ValueError(f"game {game_id}: invalid direction at {position}")
                moved, score_delta = move_board(previous, direction)
                cell = record["spawn_cell"]
                value = record["spawn_value"]
                if cell not in range(16) or value not in (1, 2) or moved[cell] != 0:
                    raise ValueError(f"game {game_id}: invalid spawn at {position}")
                moved[cell] = value
                if moved != board:
                    raise ValueError(f"game {game_id}: board mismatch at {position}")
            cumulative_score += score_delta
            timeline.append({
                "index": position,
                "board": [0 if exponent == 0 else 1 << exponent for exponent in board],
                "boardHex": f"{record['board']:016x}",
                "move": record["move"],
                "spawnCell": record["spawn_cell"],
                "spawnValue": 0 if record["spawn_value"] == 0 else 1 << record["spawn_value"],
                "searchCycles": record["search_cycles"],
                "scoreDelta": score_delta,
                "score": cumulative_score,
                "maxTile": max((1 << exponent for exponent in board), default=0),
            })
            previous = board
        summary = game_by_id[game_id]
        if len(records) != summary["replay_records"]:
            raise ValueError(f"game {game_id}: replay record count mismatch")
        if len(records) - 1 != summary["moves"]:
            raise ValueError(f"game {game_id}: replay move count mismatch")
        if records[-1]["board"] != summary["final_board"]:
            raise ValueError(f"game {game_id}: replay final board mismatch")
        prepared.append({"game": game_id, "summary": summary, "timeline": timeline})
    return prepared


def make_payload(tournament: dict, games: list[dict], prepared_replays: list[dict]) -> dict:
    for game in games:
        game["max_tile"] = 0 if game["highest_exponent"] == 0 else 1 << game["highest_exponent"]
        game["final_board_hex"] = f"{game['final_board']:016x}"
        del game["final_board"]
    tile_counts: dict[str, int] = {}
    for game in games:
        key = str(game["max_tile"])
        tile_counts[key] = tile_counts.get(key, 0) + 1
    return {
        "tournament": tournament,
        "games": games,
        "replays": prepared_replays,
        "tileCounts": tile_counts,
    }


HTML_TEMPLATE = r"""<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>FPGA 2048 Tournament Report</title>
<style>
:root{--ink:#27231f;--muted:#766e65;--paper:#f5f1e8;--panel:#fffdf8;--line:#ded5c8;--accent:#e56f45;--green:#397b62;--shadow:0 14px 38px rgba(54,43,33,.12)}
*{box-sizing:border-box} body{margin:0;color:var(--ink);background:radial-gradient(circle at 15% 0,#fff9e9 0,transparent 28%),var(--paper);font:15px/1.5 ui-sans-serif,-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}
.shell{max-width:1220px;margin:auto;padding:34px 22px 70px}.eyebrow{font-size:12px;letter-spacing:.18em;text-transform:uppercase;color:var(--accent);font-weight:800}h1{font-size:clamp(34px,5vw,62px);line-height:1;margin:8px 0 12px;letter-spacing:-.045em}.subtitle{max-width:760px;color:var(--muted);font-size:17px}
.cards{display:grid;grid-template-columns:repeat(5,1fr);gap:12px;margin:26px 0}.card,.panel{background:rgba(255,253,248,.94);border:1px solid var(--line);border-radius:18px;box-shadow:var(--shadow)}.card{padding:18px}.card b{display:block;font-size:28px;line-height:1.1}.card span{color:var(--muted);font-size:13px}.card.good b{color:var(--green)}
.grid{display:grid;grid-template-columns:minmax(380px,1.05fr) minmax(360px,.95fr);gap:18px}.panel{padding:20px}.panel h2{margin:0 0 14px;font-size:20px}.board-wrap{display:flex;align-items:center;justify-content:center;min-height:470px}.board{width:min(100%,430px);aspect-ratio:1;display:grid;grid-template-columns:repeat(4,1fr);gap:10px;background:#b9aa9d;border-radius:14px;padding:10px}.tile{display:grid;place-items:center;border-radius:9px;background:#cdc1b4;color:#665d55;font-weight:850;font-size:clamp(18px,4vw,38px);transition:transform .12s,box-shadow .12s}.tile.spawn{box-shadow:0 0 0 4px #ffec7c inset;transform:scale(.96)}
.controls{display:flex;gap:8px;align-items:center;flex-wrap:wrap;margin-top:15px}.controls button,.controls select{border:1px solid var(--line);background:#fff;border-radius:10px;padding:9px 12px;color:var(--ink);font-weight:700;cursor:pointer}.controls button.primary{background:var(--ink);color:#fff}.controls button:hover{border-color:var(--accent)}input[type=range]{flex:1;min-width:180px;accent-color:var(--accent)}
.replay-head{display:flex;justify-content:space-between;gap:14px;align-items:flex-start}.replay-head select{border:1px solid var(--line);border-radius:10px;background:#fff;padding:8px}.step-meta{display:grid;grid-template-columns:repeat(3,1fr);gap:8px;margin-top:12px}.metric{background:#f4eee4;border-radius:12px;padding:10px}.metric b{display:block;font-size:18px}.metric small{color:var(--muted)}
.spark{height:76px;width:100%;margin-top:16px}.spark polyline{fill:none;stroke:var(--accent);stroke-width:3}.spark line{stroke:#ddd3c7;stroke-width:1}.status{margin-top:10px;padding:9px 11px;background:#e9f3ed;color:#2d664f;border-radius:10px;font-size:13px}.hist{display:flex;align-items:flex-end;gap:8px;height:150px;margin:18px 0 4px}.bar{flex:1;min-width:38px;text-align:center;color:var(--muted);font-size:11px}.bar i{display:block;margin:auto;background:linear-gradient(#ef9877,var(--accent));border-radius:8px 8px 2px 2px;min-height:3px}.bar b{display:block;color:var(--ink);margin-top:4px}
.table-wrap{margin-top:18px;overflow:auto;max-height:520px;border:1px solid var(--line);border-radius:12px}table{border-collapse:collapse;width:100%;font-variant-numeric:tabular-nums}th,td{padding:9px 11px;border-bottom:1px solid #eee6db;text-align:right;white-space:nowrap}th{position:sticky;top:0;background:#f4eee4;z-index:1;font-size:12px;color:var(--muted)}th:first-child,td:first-child{text-align:left}tr[data-replay="1"]{cursor:pointer}tr[data-replay="1"]:hover{background:#fff3e8}.win{color:var(--green);font-weight:800}.loss{color:#9b5145}
.detail{display:grid;grid-template-columns:1fr 1fr;gap:18px;margin-top:18px}.foot{color:var(--muted);margin-top:18px;font-size:13px}@media(max-width:850px){.cards{grid-template-columns:repeat(2,1fr)}.grid,.detail{grid-template-columns:1fr}.board-wrap{min-height:auto}.card:last-child{grid-column:span 2}}@media(max-width:480px){.shell{padding:24px 12px 50px}.cards{grid-template-columns:1fr 1fr}.panel{padding:14px}.board{gap:6px;padding:7px}.step-meta{grid-template-columns:1fr 1fr}}
</style>
</head>
<body><main class="shell">
<div class="eyebrow">XCKU115 · queued search tournament</div><h1>2048 FPGA 比赛报告</h1><p class="subtitle">大量游戏上下文通过任务队列共享并行搜索引擎。全部局面保留最终统计，选定局保留逐步棋盘，可前后查看或自动播放。</p>
<section class="cards" id="cards"></section>
<section class="grid">
  <div class="panel"><div class="replay-head"><div><div class="eyebrow">Replay</div><h2 id="replayTitle">完整回放</h2></div><select id="gameSelect" aria-label="选择回放局"></select></div><div class="board-wrap"><div class="board" id="board"></div></div><input id="stepSlider" type="range" min="0" value="0" aria-label="回放进度"><div class="controls"><button id="first">⏮</button><button id="prev">←</button><button id="play" class="primary">▶ 自动播放</button><button id="next">→</button><button id="last">⏭</button><select id="speed" aria-label="播放速度"><option value=".25">0.25×</option><option value=".5">0.5×</option><option value="1" selected>1×</option><option value="2">2×</option><option value="4">4×</option><option value="8">8×</option></select><label><input id="loop" type="checkbox"> 循环</label></div></div>
  <div class="panel"><div class="eyebrow">Step details</div><h2 id="stepTitle">初始棋盘</h2><div class="step-meta" id="stepMeta"></div><svg class="spark" id="spark" viewBox="0 0 600 76" preserveAspectRatio="none"></svg><div class="status" id="integrity">Replay 完整性检查通过</div><h2 style="margin-top:22px">最高砖分布</h2><div class="hist" id="hist"></div></div>
</section>
<section class="detail"><div class="panel"><h2>全部比赛</h2><div class="table-wrap"><table><thead><tr><th>局</th><th>结果</th><th>步数</th><th>最高砖</th><th>最终棋盘</th><th>回放</th></tr></thead><tbody id="gameRows"></tbody></table></div></div><div class="panel"><h2>硬件配置</h2><div class="step-meta" id="hardware"></div><p class="foot">“胜利”表示该局曾达到 ≥2048；FPGA 仍继续运行到无合法移动。搜索数值为 Q23.8。随机新砖严格按 90% 的 2 和 10% 的 4，空位使用拒绝采样保持均匀。</p></div></section>
<p class="foot" id="generated"></p>
</main>
<script>const DATA=__PAYLOAD__;
const colors={0:['#cdc1b4','#665d55'],2:['#eee4da','#665d55'],4:['#ece0c9','#665d55'],8:['#f1b078','#fff'],16:['#ef965f','#fff'],32:['#ed7d59','#fff'],64:['#e95e38','#fff'],128:['#edcf72','#fff'],256:['#edcc61','#fff'],512:['#edc84f','#fff'],1024:['#e9bd36','#fff'],2048:['#e6b321','#fff'],4096:['#6b93a8','#fff'],8192:['#526f86','#fff']};
const qs=s=>document.querySelector(s), fmt=n=>Number(n).toLocaleString('zh-CN');let replayIndex=0,step=0,timer=null;
function metric(value,label){return `<div class="metric"><b>${value}</b><small>${label}</small></div>`}const t=DATA.tournament, games=DATA.games,replays=DATA.replays;const winRate=games.length?100*games.filter(g=>g.won_2048).length/games.length:0;const avgMoves=games.reduce((a,g)=>a+g.moves,0)/Math.max(1,games.length);
qs('#cards').innerHTML=metric(`${t.wins_2048}/${t.games}`,'达到 2048')+metric(`${winRate.toFixed(1)}%`,'实板胜率')+metric(fmt(Math.round(avgMoves)),'平均步数')+metric(`${t.search_engines} × ${t.workers_per_engine}`,'引擎 × workers')+metric(`${(t.wall_cycles/t.clock_mhz/1e6).toFixed(2)} s`,`${fmt(t.games)} 局墙钟时间`);qs('#cards').children[1].classList.add('good');
function renderBoard(frame){const board=qs('#board');board.innerHTML='';frame.board.forEach((value,index)=>{const d=document.createElement('div');d.className='tile'+(frame.index>0&&index===frame.spawnCell?' spawn':'');const color=colors[value]||['#3b5365','#fff'];d.style.background=color[0];d.style.color=color[1];d.textContent=value||'';board.appendChild(d)})}
function replay(){return replays[replayIndex]}function render(){const r=replay(),f=r.timeline[step],s=r.summary;renderBoard(f);qs('#stepSlider').max=r.timeline.length-1;qs('#stepSlider').value=step;qs('#replayTitle').textContent=`第 ${r.game} 局 · ${s.won_2048?'胜利':'未达 2048'}`;qs('#stepTitle').textContent=step===0?'初始棋盘':`第 ${step} 步 ${['↑ 上','↓ 下','← 左','→ 右'][f.move]}`;qs('#stepMeta').innerHTML=metric(`${step}/${r.timeline.length-1}`,'进度')+metric(fmt(f.score),'累计得分')+metric(fmt(f.maxTile),'当前最高砖')+metric(step?fmt(f.spawnValue):'—','新砖')+metric(step?f.spawnCell:'—','新砖格')+metric(step?fmt(f.searchCycles):'—','搜索周期');drawSpark(r);}
function drawSpark(r){const values=r.timeline.map(x=>Math.log2(Math.max(2,x.maxTile))),max=Math.max(...values,2),w=600,h=68;const points=values.map((v,i)=>`${i*w/Math.max(1,values.length-1)},${h-(v-1)*h/Math.max(1,max-1)}`).join(' ');const marker=step*w/Math.max(1,values.length-1);qs('#spark').innerHTML=`<line x1="0" y1="68" x2="600" y2="68"/><polyline points="${points}"/><line x1="${marker}" y1="0" x2="${marker}" y2="76" style="stroke:#27231f;stroke-dasharray:3 3"/>`}
function stop(){if(timer){clearInterval(timer);timer=null}qs('#play').textContent='▶ 自动播放'}function play(){if(timer){stop();return}qs('#play').textContent='⏸ 暂停';const tick=()=>{if(step>=replay().timeline.length-1){if(qs('#loop').checked)step=0;else{stop();return}}else step++;render()};timer=setInterval(tick,700/Number(qs('#speed').value))}
function go(value){stop();step=Math.max(0,Math.min(value,replay().timeline.length-1));render()}qs('#first').onclick=()=>go(0);qs('#prev').onclick=()=>go(step-1);qs('#next').onclick=()=>go(step+1);qs('#last').onclick=()=>go(replay().timeline.length-1);qs('#play').onclick=play;qs('#stepSlider').oninput=e=>go(Number(e.target.value));qs('#speed').onchange=()=>{if(timer){stop();play()}};
qs('#gameSelect').innerHTML=replays.map((r,i)=>`<option value="${i}">第 ${r.game} 局 · ${r.summary.moves} 步 · max ${r.summary.max_tile}</option>`).join('');qs('#gameSelect').onchange=e=>{stop();replayIndex=Number(e.target.value);step=0;render()};
qs('#hist').innerHTML=Object.entries(DATA.tileCounts).sort((a,b)=>Number(a[0])-Number(b[0])).map(([tile,count])=>`<div class="bar"><i style="height:${120*count/Math.max(...Object.values(DATA.tileCounts))}px"></i><b>${tile}</b>${count}</div>`).join('');const replayIds=new Set(replays.map(r=>r.game));qs('#gameRows').innerHTML=games.map(g=>`<tr data-game="${g.game}" data-replay="${replayIds.has(g.game)?1:0}"><td>#${g.game}</td><td class="${g.won_2048?'win':'loss'}">${g.won_2048?'胜利':'未达'}</td><td>${fmt(g.moves)}</td><td>${fmt(g.max_tile)}</td><td><code>${g.final_board_hex}</code></td><td>${replayIds.has(g.game)?'可回放':'统计'}</td></tr>`).join('');document.querySelectorAll('tr[data-replay="1"]').forEach(row=>row.onclick=()=>{replayIndex=replays.findIndex(r=>r.game===Number(row.dataset.game));step=0;stop();qs('#gameSelect').value=replayIndex;render();scrollTo({top:250,behavior:'smooth'})});
qs('#hardware').innerHTML=metric(fmt(t.games),'总比赛局数')+metric(fmt(t.active_game_count||t.games),'活跃槽位')+metric(fmt(t.node_budget),'Node budget')+metric(`Q${t.fractional_bits}`,'搜索精度')+metric(`${t.clock_mhz} MHz`,'FPGA 时钟')+metric(fmt(t.total_moves),'总步数')+metric(fmt(t.total_search_cycles),'总搜索周期');qs('#generated').textContent=`报告由 FPGA USER1/JTAG 读回数据生成 · ${new Date().toLocaleString('zh-CN')}`;
document.addEventListener('keydown',e=>{if(e.key==='ArrowLeft')go(step-1);else if(e.key==='ArrowRight')go(step+1);else if(e.key===' '){e.preventDefault();play()}else if(e.key==='Home')go(0);else if(e.key==='End')go(replay().timeline.length-1)});render();
</script></body></html>"""


def generate(input_path: Path, output_path: Path) -> None:
    tournament, games, replays = parse_capture(input_path)
    expected_games = tournament["games"]
    if tournament.get("version") not in (1, 2):
        raise ValueError(f"unsupported capture version {tournament.get('version')}")
    if tournament.get("done") != 1 or tournament.get("completed") != expected_games:
        raise ValueError("tournament is incomplete")
    if len(games) != expected_games or [game["game"] for game in games] != list(range(expected_games)):
        raise ValueError("GAME summaries are missing, duplicated, or out of order")
    if any(not game["done"] or not game["game_over"] or game["invalid"] or game["overflow"]
           for game in games):
        raise ValueError("one or more GAME summaries failed hardware integrity checks")
    if sum(game["moves"] for game in games) != tournament["total_moves"]:
        raise ValueError("summary move total does not match tournament header")
    if sum(game["won_2048"] for game in games) != tournament["wins_2048"]:
        raise ValueError("summary win total does not match tournament header")
    prepared = prepare_replays(games, replays)
    if not prepared:
        raise ValueError("capture contains no complete replay")
    payload = make_payload(tournament, games, prepared)
    encoded = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).replace("</", "<\\/")
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(HTML_TEMPLATE.replace("__PAYLOAD__", encoded), encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("capture", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    generate(args.capture, args.output)
    print(f"HTML_REPORT={args.output.resolve()}")


if __name__ == "__main__":
    main()
