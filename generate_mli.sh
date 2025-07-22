#!/bin/bash

# Script to generate MLI files for all ML files in lib/
# Uses dune exec to ensure proper build environment

echo "Generating MLI interface files..."
echo "================================"

# Find all ML files in lib/ directory
ML_FILES=($(find lib -name "*.ml" -type f | sort))

# Clean up any existing MLI files
echo "Cleaning up existing MLI files..."
rm -f lib/*.mli

# Generate MLI for each file
for ml_file in "${ML_FILES[@]}"; do
    if [ -f "$ml_file" ]; then
        mli_file="${ml_file%.ml}.mli"
        base_name=$(basename "$ml_file" .ml)
        
        echo -n "Generating $base_name.mli... "
        
        # Use dune exec to run ocamlc with proper environment
        if dune exec -- ocamlc -I _build/default/lib/.gp_2048_lib.objs/byte -open Gp_2048_lib -i "$ml_file" > "$mli_file" 2>/dev/null; then
            # Check if file is not empty and doesn't contain errors
            if [ -s "$mli_file" ] && ! grep -q "Error:" "$mli_file" 2>/dev/null; then
                echo "✓ Success"
            else
                rm -f "$mli_file"
                echo "✗ Failed (empty or contains errors)"
            fi
        else
            rm -f "$mli_file"
            echo "✗ Failed"
        fi
    else
        echo "✗ $ml_file not found"
    fi
done

echo ""
echo "Generated MLI files:"
echo "===================="
ls -la lib/*.mli 2>/dev/null || echo "No MLI files generated"

echo ""
echo "To view a generated MLI file, use: cat lib/<module>.mli"
