#!/bin/bash

echo "Testing OCaml backend integration..."

# Check if Flask server is running
if ! curl -s http://localhost:5050 > /dev/null; then
    echo "❌ Flask server not running. Starting it..."
    cd python && python app.py &
    SERVER_PID=$!
    sleep 3
else
    echo "✓ Flask server is running"
fi

# Test OCaml inference CLI directly
echo -e "\n1. Testing OCaml inference CLI directly..."
if [ -f "_build/default/inference_cli.exe" ]; then
    # Test with a sample board (some 2s and 4s)
    RESULT=$(./_build/default/inference_cli.exe 0x0000000012002100 3 2>/dev/null)
    echo "OCaml CLI output: $RESULT"
    
    # Check if output is valid JSON
    if echo "$RESULT" | grep -q '"move"'; then
        echo "✓ OCaml inference CLI working"
    else
        echo "✗ OCaml inference CLI failed"
    fi
else
    echo "✗ OCaml inference CLI not built"
    echo "Building..."
    dune build inference_cli.exe
fi

# Test the web API
echo -e "\n2. Testing web API endpoints..."

# Test root endpoint
if curl -s http://localhost:5050/ | grep -q "GP for 2048"; then
    echo "✓ Web interface loads"
else
    echo "✗ Web interface failed to load"
fi

# Test experiment results API
echo -e "\n3. Testing experiment results API..."
RESULTS=$(curl -s http://localhost:5050/api/experiment_results)
if echo "$RESULTS" | grep -q "node_limited_50_games"; then
    echo "✓ Experiment results API working"
else
    echo "✗ Experiment results API failed"
fi

echo -e "\n✅ Backend tests complete!"

# Cleanup
if [ ! -z "$SERVER_PID" ]; then
    echo "Stopping test server..."
    kill $SERVER_PID 2>/dev/null
fi