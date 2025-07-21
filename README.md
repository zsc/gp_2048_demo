# 2048 Genetic Programming Solver (OCaml)

An OCaml implementation of a 2048 game solver using expectimax search and genetic programming, achieving 30-40x performance improvement over Python.

## Directory Structure

- **lib/** - Core library (game engine, GP trees, expectimax)
- **experiments/** - Various experiments and analysis
- **benchmarks/** - Performance comparison tools
- **python/** - Original Python implementation
- **results/** - Experiment results and leaderboards
- **tests/** - Test data and controlled experiments
- **archive/** - Old/deprecated code

## Quick Start

```bash
# Build everything
dune build

# Run main program
dune exec gp_2048

# Test score-based strategy (best performer)
dune exec ./test_score_based.exe

# Run experiments
cd experiments && dune exec ./experiment_node_limited.exe
```

## Key Results

**Best Strategy**: Score-based dynamic node allocation
- Average score: 8,788
- Speed: 11.4 games/sec
- Adapts computation based on game progress

See CLAUDE.md for detailed documentation and results.