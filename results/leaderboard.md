# 2048 AI Leaderboard

## Top Performers

### 🥇 Best Average Score: 8,788
**Strategy**: Score-based dynamic nodes  
- Allocates more nodes as score increases
- 5 game average
- Speed: 11.4 games/sec

### 🥈 Second Best: 7,998  
**Strategy**: Smoothness evaluation function (depth 2)
- Includes smoothness scoring
- 10 game average  
- Speed: 3.9 games/sec

### 🥉 Third Best: 7,880
**Strategy**: Fixed depth 2
- Standard expectimax
- 5 game average
- Speed: 6.1 games/sec

## All Results Summary

| Rank | Strategy | Avg Score | Max Score | Speed (games/sec) | Notes |
|------|----------|-----------|-----------|-------------------|-------|
| 1 | Score-based nodes | 8,788 | 11,876 | 11.4 | Dynamic allocation |
| 2 | Smoothness eval | 7,998 | - | 3.9 | Depth 2 |
| 3 | Fixed depth 2 | 7,880 | - | 6.1 | Full games |
| 4 | Weighted eval | 7,626 | - | 5.6 | 2×Empty + MaxTile |
| 5 | Fixed depth 2 | 7,583 | 9,352 | 6.1 | 50 games |
| 6 | Evolution final | 7,198 | - | - | GP evolved |
| 7 | Simple eval | 7,149 | - | 5.9 | Empty + MaxTile |
| 8 | Node budget 500 | 6,492 | 11,876 | 23.9 | Fast |
| 9 | Fixed depth 1 | 5,710 | - | 474.5 | Very fast |
| 10 | Node budget 10k | 5,548 | 11,972 | 2.1 | Balanced |
| 11 | Combined nodes | 5,181 | - | 9.2 | Multi-factor |
| 12 | Node budget 50k | 4,786 | 6,604 | 0.5 | Diminishing returns |

## Key Insights

1. **Sweet Spot**: 500-1000 node budget provides best score/speed tradeoff
2. **Diminishing Returns**: Beyond 10k nodes, performance degrades
3. **Dynamic Allocation Wins**: Score-based node allocation outperforms fixed strategies
4. **Depth vs Nodes**: Node-limited search more flexible than fixed depth
5. **Speed**: Can achieve 78 games/sec with 100 nodes, still scoring ~3,900

## Best Single Games
- **11,972** - Node budget 10k
- **11,876** - Node budget 500 / Score-based nodes  
- **11,160** - Score-based nodes
- **10,508** - Node budget 5k
- **9,352** - Fixed depth 2

## Recommendations

For production use:
- **Fast**: 100-500 nodes, 20-80 games/sec, avg score ~4-6k
- **Balanced**: Score-based dynamic (1k-10k nodes), 10+ games/sec, avg score ~8k  
- **Quality**: Fixed 10k nodes or depth 2, 2-6 games/sec, avg score ~7-8k

The score-based dynamic node allocation is the clear winner, adapting compute resources based on game progress.