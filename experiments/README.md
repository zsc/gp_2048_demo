# 2048 GP Experiments

This directory contains various experiments for the 2048 GP solver.

## Experiments

### experiment_ocaml.ml
- Basic experiments comparing search depths and GP programs
- Tests evolution over multiple generations

### experiment_ocaml_fast.ml
- Faster version with periodic output to avoid timeouts
- Saves results incrementally to file

### experiment_dynamic_depth.ml
- Tests dynamic depth strategies based on empty cells
- Profiles search performance by board state

### experiment_node_limited.ml
- Implements node-limited expectimax search
- Tests various node budget strategies
- Contains the winning score-based dynamic allocation

### gp_evolution_leaderboard.ml
- Advanced GP evolution with leaderboard tracking
- Tests multiple evolution strategies
- Maintains top performing programs

## Running Experiments

```bash
# Build all experiments
dune build

# Run specific experiment
dune exec experiments/experiment_node_limited.exe
```