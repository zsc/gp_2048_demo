#!/usr/bin/env python
"""Simple test for the Flask app"""

import time
import subprocess
import requests
import json
import os
import signal

def test_flask_app():
    print("Testing Flask app with OCaml backend...")
    
    # Start Flask server
    print("Starting Flask server...")
    server_process = subprocess.Popen(
        ["python", "app.py"],
        cwd="python",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        preexec_fn=os.setsid
    )
    
    # Wait for server to start
    time.sleep(3)
    
    try:
        # Test 1: Check if server is running
        print("\n1. Testing server availability...")
        response = requests.get("http://localhost:5050")
        if response.status_code == 200:
            print("✓ Server is running")
        else:
            print(f"✗ Server returned status {response.status_code}")
            
        # Test 2: Check experiment results API
        print("\n2. Testing experiment results API...")
        response = requests.get("http://localhost:5050/api/experiment_results")
        if response.status_code == 200:
            data = response.json()
            if "node_limited_50_games" in data:
                print("✓ Experiment results API working")
                print(f"  Found {len(data)} experiment results")
            else:
                print("✗ Experiment results missing expected data")
        else:
            print(f"✗ API returned status {response.status_code}")
            
        # Test 3: Test OCaml inference directly
        print("\n3. Testing OCaml inference CLI...")
        if os.path.exists("_build/default/inference_cli.exe"):
            result = subprocess.run(
                ["./_build/default/inference_cli.exe", "0x0000000012002100", "3"],
                capture_output=True,
                text=True
            )
            if result.returncode == 0:
                output = json.loads(result.stdout)
                print(f"✓ OCaml inference working: move={output['move']}, time={output['time_ms']}ms")
            else:
                print(f"✗ OCaml inference failed: {result.stderr}")
        else:
            print("✗ OCaml inference CLI not found")
            
        print("\n✅ All tests completed!")
        
    except Exception as e:
        print(f"\n❌ Test failed: {str(e)}")
        
    finally:
        # Stop server
        print("\nStopping server...")
        os.killpg(os.getpgid(server_process.pid), signal.SIGTERM)
        server_process.wait()

if __name__ == "__main__":
    test_flask_app()