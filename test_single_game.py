#!/usr/bin/env python
"""Quick test of a single AI game"""

import subprocess
import time
import requests
import json
import random

# Simple game state tracking
board = [[0 for _ in range(4)] for _ in range(4)]
score = 0

def add_random_tile():
    """Add a random tile to the board"""
    empty = [(i, j) for i in range(4) for j in range(4) if board[i][j] == 0]
    if empty:
        i, j = random.choice(empty)
        board[i][j] = 2 if random.random() < 0.9 else 4

# Start Flask app
print("Starting Flask app...")
app_process = subprocess.Popen(
    ["python", "app.py"],
    cwd="python",
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE
)

time.sleep(3)

try:
    # Initialize board
    add_random_tile()
    add_random_tile()
    
    print("Testing AI moves with simple_fast.json model...")
    
    # Test 10 moves
    for move_num in range(10):
        # Get AI move
        response = requests.post(
            "http://localhost:5050/api/get_move",
            json={'board': board, 'model': 'simple_fast.json'},
            headers={'Content-Type': 'application/json'}
        )
        
        if response.status_code == 200:
            data = response.json()
            print(f"Move {move_num + 1}: direction={data['move']}, time={data['inference_time']:.1f}ms, budget={data['node_budget']}")
            
            # Simulate board change (just add a random tile for testing)
            if data['move'] != -1:
                add_random_tile()
        else:
            print(f"Error: {response.status_code}")
            break
    
    print("\nTest completed successfully!")
    
finally:
    app_process.terminate()
    app_process.wait()
    print("Flask app stopped.")