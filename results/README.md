# 2048 GP Results

This directory contains experimental results and leaderboards.

## Files

### leaderboard.md
- Comprehensive AI performance leaderboard
- Rankings of all tested strategies
- Key insights and recommendations

### experiment_results.txt
- Results from basic experiments
- Depth comparison, GP program comparison, evolution tests

### node_limited_results.txt
- Detailed results from node-limited search experiments
- Shows performance vs node budget trade-offs

### benchmark_results.txt
- Benchmark comparisons between different implementations

### test_controlled.txt
- Controlled test results with fixed random sequences

## Key Findings

1. **Best Strategy**: Score-based dynamic node allocation (8,788 avg score)
2. **Sweet Spot**: 500-1000 nodes for best score/speed balance
3. **Speed**: Can achieve 78 games/sec with 100 nodes
4. **OCaml Performance**: 30-40x faster than Python implementation