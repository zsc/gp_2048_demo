#!/usr/bin/env python3
"""Test script to verify both search modes work correctly"""

import subprocess
import json

# Test the OCaml CLI with both modes
print("Testing OCaml inference CLI with both search modes...")

# Test 1: Node budget mode
print("\n1. Testing node budget mode:")
cmd = ["./_build/default/inference_cli.exe", "--play-game", "python/models/simple_fast.json", "42", "--node-budget", "100"]
result = subprocess.run(cmd, capture_output=True, text=True)
if result.returncode == 0:
    data = json.loads(result.stdout)
    print(f"  ✓ Node budget mode works! Final score: {data['final_score']}, moves: {data['total_moves']}")
    print(f"    Node budget used: {data.get('node_budget', 'N/A')}")
else:
    print(f"  ✗ Node budget mode failed: {result.stderr}")

# Test 2: Fixed depth mode
print("\n2. Testing fixed depth mode:")
cmd = ["./_build/default/inference_cli.exe", "--play-game", "python/models/simple_fast.json", "42", "--search-depth", "2"]
result = subprocess.run(cmd, capture_output=True, text=True)
if result.returncode == 0:
    data = json.loads(result.stdout)
    print(f"  ✓ Fixed depth mode works! Final score: {data['final_score']}, moves: {data['total_moves']}")
    print(f"    Search depth used: {data.get('search_depth', 'N/A')}")
else:
    print(f"  ✗ Fixed depth mode failed: {result.stderr}")

# Test 3: Default mode (should use model's node budget)
print("\n3. Testing default mode:")
cmd = ["./_build/default/inference_cli.exe", "--play-game", "python/models/simple_fast.json", "42"]
result = subprocess.run(cmd, capture_output=True, text=True)
if result.returncode == 0:
    data = json.loads(result.stdout)
    print(f"  ✓ Default mode works! Final score: {data['final_score']}, moves: {data['total_moves']}")
    print(f"    Node budget used: {data.get('node_budget', 'N/A')} (from model)")
else:
    print(f"  ✗ Default mode failed: {result.stderr}")

print("\n✅ All tests completed!")