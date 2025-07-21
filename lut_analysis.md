# Lookup Table State Space Analysis

## Current Representation
- Each tile is 4 bits (0-15, representing log2 of tile value)
- Each row is 16 bits (4 tiles × 4 bits)
- Total states per row: 2^16 = 65,536

## Memory Requirements

### Current LUTs (already implemented):
- left_table: 65,536 × 4 bytes = 256 KB
- right_table: 65,536 × 4 bytes = 256 KB  
- score_table: 65,536 × 4 bytes = 256 KB
- **Total existing**: 768 KB

### Proposed New LUTs:
- monotonicity_table: 65,536 × 4 bytes = 256 KB
- smoothness_table: 65,536 × 4 bytes = 256 KB
- **Total new**: 512 KB

**Combined total**: 1.28 MB (very reasonable!)

## State Reduction Options (if needed)

### Option 1: Threshold-based reduction
- Treat tiles > 2048 (log2 > 11) as 2048
- Reduces bits per tile from 4 to 3.5 effective bits
- States: ~46,000 (modest reduction)

### Option 2: Coarse-grained representation  
- Group tiles: 0, 2, 4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048+
- 12 states per tile = ~3.6 bits
- States per row: 12^4 = 20,736
- Memory per LUT: 81 KB (75% reduction)

### Option 3: Dynamic programming
- Only compute/store rows that actually appear in games
- Most high-value combinations (e.g., [2048, 1024, 512, 256]) are rare
- Could reduce effective states by 50-80%

## Recommendation

**Go with full 65,536-state LUTs** because:
1. Memory usage (512 KB) is trivial on modern systems
2. Computation is simple - one pass through 65,536 states at startup
3. No runtime overhead for edge case handling
4. Perfect alignment with existing move/score tables

## Implementation Benefits

For a typical expectimax search:
- Depth 3 search evaluates ~1000 board positions
- Each board evaluation computes smoothness/monotonicity (16 cells, multiple neighbors)
- **Current**: ~50-100 operations per board
- **With LUT**: 4 lookups per board
- **Speedup**: 10-25x for evaluation functions