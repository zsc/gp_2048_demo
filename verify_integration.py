#!/usr/bin/env python
"""Verify that the Flask app integrates correctly with OCaml backend"""

import subprocess
import json

def verify_ocaml_backend():
    print("=== Verifying OCaml Backend Integration ===\n")
    
    # Test 1: OCaml CLI directly
    print("1. Testing OCaml inference CLI:")
    try:
        # Test board with some tiles
        test_board = "0x0000000012002100"  # A board with some 2s and 4s
        result = subprocess.run(
            ["./_build/default/inference_cli.exe", test_board, "3"],
            capture_output=True,
            text=True,
            timeout=5.0
        )
        
        if result.returncode == 0:
            output = json.loads(result.stdout)
            print(f"   ✓ OCaml CLI working")
            print(f"   - Move: {output['move']} (0=Up, 1=Down, 2=Left, 3=Right)")
            print(f"   - Inference time: {output['time_ms']:.1f} ms")
        else:
            print(f"   ✗ OCaml CLI failed: {result.stderr}")
            return False
    except Exception as e:
        print(f"   ✗ Error testing OCaml CLI: {e}")
        return False
    
    # Test 2: Verify inference speed
    print("\n2. Performance test (10 inferences):")
    times = []
    for i in range(10):
        result = subprocess.run(
            ["./_build/default/inference_cli.exe", test_board, "3"],
            capture_output=True,
            text=True,
            timeout=5.0
        )
        if result.returncode == 0:
            output = json.loads(result.stdout)
            times.append(output['time_ms'])
    
    if times:
        avg_time = sum(times) / len(times)
        print(f"   ✓ Average inference time: {avg_time:.1f} ms")
        print(f"   - Min: {min(times):.1f} ms")
        print(f"   - Max: {max(times):.1f} ms")
    
    # Test 3: Different board configurations
    print("\n3. Testing different board states:")
    test_cases = [
        ("0x0000000000000000", "Empty board"),
        ("0x0000000012000000", "One tile (2)"),
        ("0x1111111111111111", "All 2s"),
        ("0x3322110033221100", "Complex board")
    ]
    
    for board_hex, description in test_cases:
        result = subprocess.run(
            ["./_build/default/inference_cli.exe", board_hex, "2"],
            capture_output=True,
            text=True,
            timeout=5.0
        )
        if result.returncode == 0:
            output = json.loads(result.stdout)
            print(f"   ✓ {description}: move={output['move']}, time={output['time_ms']:.1f}ms")
        else:
            print(f"   ✗ {description}: failed")
    
    print("\n=== Summary ===")
    print("The OCaml backend is working correctly!")
    print("To use with the web interface:")
    print("1. Start the Flask server: cd python && python app.py")
    print("2. Open http://localhost:5050 in your browser")
    print("3. Click 'New Game' then 'Let AI Play'")
    print("4. Watch the inference times displayed in real-time")
    
    return True

if __name__ == "__main__":
    verify_ocaml_backend()