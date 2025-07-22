# Expectimax Memoization Analysis

## Current Algorithm Structure

The expectimax algorithm alternates between:
1. **MAX nodes** (player's turn): Choose the best move among Up/Down/Left/Right
2. **EXPECT nodes** (computer's turn): Calculate expected value over all empty cells with 90% chance of 2 and 10% chance of 4

## Potential for Repeated Evaluations

### 1. **Board Position Repetitions**
- The same board position can be reached through different move sequences
- Example: Up→Right could lead to the same position as Right→Up
- Within a single search tree, we might evaluate the same position multiple times

### 2. **Symmetry Opportunities**
- 2048 boards have rotational and reflective symmetries
- A board rotated 90° is strategically equivalent
- Could reduce search space by up to 8x (4 rotations × 2 reflections)

### 3. **Transposition Table Benefits**
- Store (board_hash, depth, value) tuples
- Reuse evaluations when the same position appears at the same depth
- Particularly beneficial for deeper searches where convergence is more likely

## Implementation Challenges

### 1. **Board Hashing**
- Need a fast, collision-resistant hash function for int64 boards
- OCaml's Hashtbl.hash should work well for int64 values

### 2. **Memory Management**
- Transposition table can grow large
- Need size limits and replacement policy (e.g., LRU)
- Clear between games to avoid stale entries

### 3. **Program Dependency**
- Memoized values are specific to each GP program
- Cannot share cache between different evaluation functions
- Cache must be cleared when switching programs

## Profiling Needed

To quantify the benefit, we should measure:
1. How many duplicate board evaluations occur in typical games
2. Distribution of depths where duplicates appear
3. Memory usage vs. speedup tradeoff

## Recommended Implementation

```ocaml
module BoardCache = struct
  type t = (int64 * int, float) Hashtbl.t
  
  let create size = Hashtbl.create size
  
  let make_key board depth = (board, depth)
  
  let find_opt cache board depth = 
    Hashtbl.find_opt cache (make_key board depth)
    
  let add cache board depth value =
    Hashtbl.add cache (make_key board depth) value
end
```

## Expected Benefits

- **Shallow searches (depth 1-2)**: Minimal benefit, few repeated positions
- **Medium searches (depth 3-4)**: Moderate benefit, some transpositions
- **Deep searches (depth 5+)**: Significant benefit, many repeated positions
- **Node-limited search**: High benefit, as partial evaluations are common

## Next Steps

1. Implement basic memoization for max_value and expect_value
2. Add counters to measure cache hit rates
3. Experiment with different cache sizes
4. Consider symmetry reduction as a follow-up optimization