#!/usr/bin/env python
"""Generate random tape for 2048 game testing."""

import random
import sys

def generate_random_tape(num_events, seed=None, filename="random_tape.txt"):
    """Generate a random tape file for deterministic game replay.
    
    Args:
        num_events: Number of random events to generate
        seed: Random seed for reproducibility
        filename: Output filename
    """
    if seed is not None:
        random.seed(seed)
    
    with open(filename, 'w') as f:
        f.write("# Random tape for 2048 game\n")
        f.write("# Format: position value\n")
        f.write("# position: 0-15 (relative to empty cells)\n")
        f.write("# value: 1=2, 2=4\n")
        f.write(f"# Generated with seed: {seed}\n\n")
        
        for i in range(num_events):
            # Position is relative to empty cells (0-15 covers all cases)
            position = random.randint(0, 15)
            # 90% chance of 2 (value=1), 10% chance of 4 (value=2)
            value = 1 if random.random() < 0.9 else 2
            f.write(f"{position} {value}\n")
    
    print(f"Generated {num_events} random events to {filename}")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python generate_random_tape.py <num_events> [seed] [filename]")
        sys.exit(1)
    
    num_events = int(sys.argv[1])
    seed = int(sys.argv[2]) if len(sys.argv) > 2 else None
    filename = sys.argv[3] if len(sys.argv) > 3 else "random_tape.txt"
    
    generate_random_tape(num_events, seed, filename)