#!/usr/bin/env python
"""Generate lookup tables for 2048 game and save to files."""

def int_to_row(x):
    return [(x >> (4*i)) & 0xF for i in range(4)]

def row_to_int(row):
    out = 0
    for i, v in enumerate(row):
        out |= (v << (4*i))
    return out

def move_row_left(row):
    nz = [x for x in row if x]
    merged, sc, i = [], 0, 0
    while i < len(nz):
        if i+1 < len(nz) and nz[i] == nz[i+1]:
            merged.append(nz[i]+1)
            sc += (1 << (nz[i]+1))
            i += 2
        else:
            merged.append(nz[i])
            i += 1
    res = merged + [0]*(4-len(merged))
    return res, sc

def generate_tables():
    """Generate all lookup tables."""
    left_table = [0] * 65536
    right_table = [0] * 65536
    score_table = [0] * 65536
    
    for i in range(65536):
        row = int_to_row(i)
        
        # Left move
        left_r, sc_l = move_row_left(row)
        left_table[i] = row_to_int(left_r)
        score_table[i] = sc_l
        
        # Right move
        right_r, sc_r = move_row_left(row[::-1])
        right_table[i] = row_to_int(right_r[::-1])
    
    return left_table, right_table, score_table

def save_tables():
    """Generate and save tables to files."""
    left_table, right_table, score_table = generate_tables()
    
    # Check max values
    print(f"Max values: left={max(left_table)}, right={max(right_table)}, score={max(score_table)}")
    
    # Save as binary files for efficiency
    with open('left_table.bin', 'wb') as f:
        for val in left_table:
            # Use 4 bytes to be safe
            f.write(val.to_bytes(4, 'little'))
    
    with open('right_table.bin', 'wb') as f:
        for val in right_table:
            f.write(val.to_bytes(4, 'little'))
    
    with open('score_table.bin', 'wb') as f:
        for val in score_table:
            f.write(val.to_bytes(4, 'little'))
    
    print("Generated lookup tables:")
    print(f"  left_table.bin: {len(left_table)} entries")
    print(f"  right_table.bin: {len(right_table)} entries")
    print(f"  score_table.bin: {len(score_table)} entries")
    
    # Test a few values
    print("\nTest values:")
    test_rows = [0x0112, 0x1234, 0x0000, 0xFFFF]
    for row in test_rows:
        print(f"  Row {row:04x}: left={left_table[row]:04x}, right={right_table[row]:04x}, score={score_table[row]}")

if __name__ == "__main__":
    save_tables()