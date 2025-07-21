#!/bin/bash
# Run benchmarks and compare results

echo "=== Benchmark Comparison: Python vs OCaml ==="
echo ""

# Make sure we have a test tape
if [ ! -f test_tape.txt ]; then
    echo "Generating test tape..."
    python generate_random_tape.py 1000 42 test_tape.txt
fi

# Build OCaml
echo "Building OCaml..."
dune build benchmark_comparison.exe

echo ""
echo "Running Python benchmark..."
echo "------------------------"
time python benchmark_comparison.py

echo ""
echo "Running OCaml benchmark..."
echo "------------------------"
time dune exec ./benchmark_comparison.exe

echo ""
echo "=== Bit-level Comparison ==="
echo ""

# Create a simple comparison test
cat > test_bit_comparison.py << 'EOF'
#!/usr/bin/env python
import subprocess
from game import Game2048

# Test specific board operations
test_board = 0x1234567890ABCDEF

Game2048._init_tables()
left, score_left, _ = Game2048.move_left(test_board)
right, score_right, _ = Game2048.move_right(test_board)
up, score_up, _ = Game2048.move_up(test_board)
down, score_down, _ = Game2048.move_down(test_board)

print(f"Python results for board {test_board:016x}:")
print(f"  Left:  {left:016x} (score: {score_left})")
print(f"  Right: {right:016x} (score: {score_right})")
print(f"  Up:    {up:016x} (score: {score_up})")
print(f"  Down:  {down:016x} (score: {score_down})")
EOF

cat > test_bit_comparison.ml << 'EOF'
open Gp_2048_lib.Game

let () =
  let test_board = 0x1234567890ABCDEFL in
  
  let left = move_left test_board in
  let right = move_right test_board in
  let up = move_up test_board in
  let down = move_down test_board in
  
  Printf.printf "OCaml results for board %016Lx:\n" test_board;
  Printf.printf "  Left:  %016Lx (score: %d)\n" left (get_score_for_move test_board `Left);
  Printf.printf "  Right: %016Lx (score: %d)\n" right (get_score_for_move test_board `Right);
  Printf.printf "  Up:    %016Lx (score: %d)\n" up (get_score_for_move test_board `Up);
  Printf.printf "  Down:  %016Lx (score: %d)\n" down (get_score_for_move test_board `Down)
EOF

echo "Bit-level operation comparison:"
python test_bit_comparison.py
echo ""
dune exec ocaml test_bit_comparison.ml

# Clean up
rm -f test_bit_comparison.py test_bit_comparison.ml