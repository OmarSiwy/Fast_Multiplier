#!/usr/bin/env python3
"""Generate test data for prefix_tree.sv"""

import random
import os
import argparse
import math


def compute_prefix_tree(g_in, p_in, a_in, width, technique):
    """
    Compute expected outputs for prefix tree using the specified technique.
    
    This function simulates the parallel prefix computation to generate
    the expected outputs for testing.
    
    Args:
        g_in: List of generate inputs (LSB to MSB)
        p_in: List of propagate inputs (LSB to MSB)
        a_in: List of auxiliary inputs (LSB to MSB)
        width: Bit width
        technique: "brent-kung", "sklansky", or "kogge-stone"
    
    Returns:
        Tuple of (g_out, p_out, a_out) as lists
    """
    
    def prefix_op(g_hi, p_hi, a_hi, g_lo, p_lo, a_lo):
        """Single prefix cell operation"""
        g_out = g_hi | (p_hi & g_lo)
        p_out = p_hi & p_lo
        a_out = a_hi | (p_hi & a_lo)
        return g_out, p_out, a_out
    
    # Initialize levels - level 0 is inputs
    levels = {}
    levels[0] = {'g': list(g_in), 'p': list(p_in), 'a': list(a_in)}
    
    num_levels = math.ceil(math.log2(width))
    
    if technique == "kogge-stone":
        # Kogge-Stone: log2(n) levels, maximum parallelism
        for level in range(1, num_levels + 1):
            levels[level] = {'g': [0]*width, 'p': [0]*width, 'a': [0]*width}
            step = 1 << (level - 1)  # 2^(level-1)
            
            for i in range(width):
                if i < step:
                    # Buffer from previous level
                    levels[level]['g'][i] = levels[level-1]['g'][i]
                    levels[level]['p'][i] = levels[level-1]['p'][i]
                    levels[level]['a'][i] = levels[level-1]['a'][i]
                else:
                    # Compute prefix
                    g_hi = levels[level-1]['g'][i]
                    p_hi = levels[level-1]['p'][i]
                    a_hi = levels[level-1]['a'][i]
                    g_lo = levels[level-1]['g'][i-step]
                    p_lo = levels[level-1]['p'][i-step]
                    a_lo = levels[level-1]['a'][i-step]
                    
                    g, p, a = prefix_op(g_hi, p_hi, a_hi, g_lo, p_lo, a_lo)
                    levels[level]['g'][i] = g
                    levels[level]['p'][i] = p
                    levels[level]['a'][i] = a
    
    elif technique == "sklansky":
        # Sklansky: log2(n) levels, divide-and-conquer
        for level in range(1, num_levels + 1):
            levels[level] = {'g': [0]*width, 'p': [0]*width, 'a': [0]*width}
            step = 1 << level  # 2^level
            half_step = step >> 1
            
            for i in range(width):
                # Determine position within block
                block_num = i // step
                pos_in_block = i % step
                
                if pos_in_block < half_step:
                    # First half of block: buffer
                    levels[level]['g'][i] = levels[level-1]['g'][i]
                    levels[level]['p'][i] = levels[level-1]['p'][i]
                    levels[level]['a'][i] = levels[level-1]['a'][i]
                else:
                    # Second half: combine with last of first half
                    left_idx = i
                    right_idx = block_num * step + half_step - 1
                    
                    g_hi = levels[level-1]['g'][left_idx]
                    p_hi = levels[level-1]['p'][left_idx]
                    a_hi = levels[level-1]['a'][left_idx]
                    g_lo = levels[level-1]['g'][right_idx]
                    p_lo = levels[level-1]['p'][right_idx]
                    a_lo = levels[level-1]['a'][right_idx]
                    
                    g, p, a = prefix_op(g_hi, p_hi, a_hi, g_lo, p_lo, a_lo)
                    levels[level]['g'][i] = g
                    levels[level]['p'][i] = p
                    levels[level]['a'][i] = a
    
    elif technique == "brent-kung":
        # Brent-Kung: 2*log2(n) - 1 levels, area-optimized
        num_levels_up = math.ceil(math.log2(width))
        
        # Up-sweep phase
        for level in range(1, num_levels_up + 1):
            levels[level] = {'g': [0]*width, 'p': [0]*width, 'a': [0]*width}
            step = 1 << level  # 2^level
            
            for i in range(width):
                if (i + 1) % step == 0:
                    # Compute at positions 2^k - 1
                    g_hi = levels[level-1]['g'][i]
                    p_hi = levels[level-1]['p'][i]
                    a_hi = levels[level-1]['a'][i]
                    g_lo = levels[level-1]['g'][i - (step >> 1)]
                    p_lo = levels[level-1]['p'][i - (step >> 1)]
                    a_lo = levels[level-1]['a'][i - (step >> 1)]
                    
                    g, p, a = prefix_op(g_hi, p_hi, a_hi, g_lo, p_lo, a_lo)
                    levels[level]['g'][i] = g
                    levels[level]['p'][i] = p
                    levels[level]['a'][i] = a
                else:
                    # Buffer
                    levels[level]['g'][i] = levels[level-1]['g'][i]
                    levels[level]['p'][i] = levels[level-1]['p'][i]
                    levels[level]['a'][i] = levels[level-1]['a'][i]
        
        # Down-sweep phase
        for level in range(num_levels_up + 1, 2 * num_levels_up):
            levels[level] = {'g': [0]*width, 'p': [0]*width, 'a': [0]*width}
            offset = level - num_levels_up
            step = 1 << (num_levels_up - offset)
            half_step = step >> 1
            
            for i in range(width):
                mod_val = (i + 1) % step
                if mod_val == half_step:
                    # Compute prefix
                    right_idx = ((i + 1) // step) * step - 1
                    if right_idx >= 0 and right_idx < width:
                        g_hi = levels[level-1]['g'][i]
                        p_hi = levels[level-1]['p'][i]
                        a_hi = levels[level-1]['a'][i]
                        g_lo = levels[level-1]['g'][right_idx]
                        p_lo = levels[level-1]['p'][right_idx]
                        a_lo = levels[level-1]['a'][right_idx]
                        
                        g, p, a = prefix_op(g_hi, p_hi, a_hi, g_lo, p_lo, a_lo)
                        levels[level]['g'][i] = g
                        levels[level]['p'][i] = p
                        levels[level]['a'][i] = a
                    else:
                        levels[level]['g'][i] = levels[level-1]['g'][i]
                        levels[level]['p'][i] = levels[level-1]['p'][i]
                        levels[level]['a'][i] = levels[level-1]['a'][i]
                else:
                    # Buffer
                    levels[level]['g'][i] = levels[level-1]['g'][i]
                    levels[level]['p'][i] = levels[level-1]['p'][i]
                    levels[level]['a'][i] = levels[level-1]['a'][i]
        
        max_level = 2 * num_levels_up - 1
        return levels[max_level]['g'], levels[max_level]['p'], levels[max_level]['a']
    
    return levels[num_levels]['g'], levels[num_levels]['p'], levels[num_levels]['a']


def generate_test_data(width=8, num_tests=64, exhaustive=False, 
                       technique="kogge-stone", output_dir="./data"):
    """
    Generate random or exhaustive test vectors for prefix_tree.sv

    Args:
        width: Bit width of the prefix tree
        num_tests: Number of random test cases (ignored if exhaustive=True)
        exhaustive: If True, generate all 2^(3*width) possible input combinations
                   (only practical for small widths like 2-4)
        technique: Prefix tree technique ("kogge-stone", "brent-kung", "sklansky")
        output_dir: Output directory for test data files
    """

    os.makedirs(output_dir, exist_ok=True)

    g_in_vals, p_in_vals, a_in_vals = [], [], []
    g_out_vals, p_out_vals, a_out_vals = [], [], []

    if exhaustive:
        if width > 4:
            print(f"Warning: Exhaustive testing for width={width} would generate "
                  f"{2**(3*width)} tests. Limiting to {num_tests} random tests.")
            exhaustive = False
        else:
            # Generate all possible input combinations
            total_combos = 2 ** (3 * width)
            print(f"Generating exhaustive test cases: {total_combos} tests")
            
            for combo in range(total_combos):
                g_in = [(combo >> (i)) & 1 for i in range(width)]
                p_in = [(combo >> (width + i)) & 1 for i in range(width)]
                a_in = [(combo >> (2*width + i)) & 1 for i in range(width)]
                
                g_out, p_out, a_out = compute_prefix_tree(g_in, p_in, a_in, width, technique)
                
                g_in_vals.append(int(''.join(str(b) for b in reversed(g_in)), 2))
                p_in_vals.append(int(''.join(str(b) for b in reversed(p_in)), 2))
                a_in_vals.append(int(''.join(str(b) for b in reversed(a_in)), 2))
                g_out_vals.append(int(''.join(str(b) for b in reversed(g_out)), 2))
                p_out_vals.append(int(''.join(str(b) for b in reversed(p_out)), 2))
                a_out_vals.append(int(''.join(str(b) for b in reversed(a_out)), 2))
    
    if not exhaustive:
        # Generate random test cases
        for _ in range(num_tests):
            g_in = [random.randint(0, 1) for _ in range(width)]
            p_in = [random.randint(0, 1) for _ in range(width)]
            a_in = [random.randint(0, 1) for _ in range(width)]
            
            g_out, p_out, a_out = compute_prefix_tree(g_in, p_in, a_in, width, technique)
            
            # Convert bit arrays to hex values
            g_in_vals.append(int(''.join(str(b) for b in reversed(g_in)), 2))
            p_in_vals.append(int(''.join(str(b) for b in reversed(p_in)), 2))
            a_in_vals.append(int(''.join(str(b) for b in reversed(a_in)), 2))
            g_out_vals.append(int(''.join(str(b) for b in reversed(g_out)), 2))
            p_out_vals.append(int(''.join(str(b) for b in reversed(p_out)), 2))
            a_out_vals.append(int(''.join(str(b) for b in reversed(a_out)), 2))

    # Write to hex files
    def write_hex(filename, values, width_bits):
        path = os.path.join(output_dir, filename)
        hex_width = (width_bits + 3) // 4  # Number of hex digits needed
        with open(path, "w") as f:
            for val in values:
                f.write(f"{val:0{hex_width}x}\n")

    write_hex("g_in.hex", g_in_vals, width)
    write_hex("p_in.hex", p_in_vals, width)
    write_hex("a_in.hex", a_in_vals, width)
    write_hex("g_out.hex", g_out_vals, width)
    write_hex("p_out.hex", p_out_vals, width)
    write_hex("a_out.hex", a_out_vals, width)

    print(f"\nGenerated {len(g_in_vals)} test vectors for {technique} prefix_tree")
    print(f"Width: {width} bits")
    print(f"Files written to {output_dir}/\n")
    
    # Print first few test cases
    for i in range(min(5, len(g_in_vals))):
        print(f"Test {i}:")
        print(f"  g_in={g_in_vals[i]:0{(width+3)//4}x} "
              f"p_in={p_in_vals[i]:0{(width+3)//4}x} "
              f"a_in={a_in_vals[i]:0{(width+3)//4}x}")
        print(f"  g_out={g_out_vals[i]:0{(width+3)//4}x} "
              f"p_out={p_out_vals[i]:0{(width+3)//4}x} "
              f"a_out={a_out_vals[i]:0{(width+3)//4}x}")


def export_defines(args):
    """Generate tb/top.h with test configuration"""
    os.makedirs(args.header, exist_ok=True)
    header_path = os.path.join(args.header, "top.h")

    # Map technique names to numbers
    technique_map = {
        'kogge-stone': 0,
        'sklansky': 1,
        'brent-kung': 2
    }

    with open(header_path, "w") as f:
        f.write(f"`define TESTS {args.num_tests}\n")
        f.write(f"`define W {args.width}\n")
        f.write(f"`define TECHNIQUE {technique_map[args.technique]}\n")

    print(f"Header file written to: {header_path}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Generate prefix_tree test data")
    parser.add_argument(
        "-w", "--width",
        type=int,
        default=8,
        help="Bit width of prefix tree (default: 8)",
    )
    parser.add_argument(
        "-n", "--num-tests",
        type=int,
        default=64,
        help="Number of test cases (default: 64)",
    )
    parser.add_argument(
        "-e", "--exhaustive",
        action="store_true",
        help="Generate exhaustive test cases (only practical for width <= 4)",
    )
    parser.add_argument(
        "-t", "--technique",
        type=str,
        default="kogge-stone",
        choices=["kogge-stone", "brent-kung", "sklansky"],
        help="Prefix tree technique (default: kogge-stone)",
    )
    parser.add_argument(
        "-o", "--output",
        type=str,
        default="data/",
        help="Output directory (default: data/)",
    )
    parser.add_argument(
        "-r", "--header",
        type=str,
        default="tb/",
        help="Output directory for top.h header file (default: tb/)",
    )
    parser.add_argument(
        "-p", "--pipeline",
        type=int,
        default=0,
        help="Pipeline stages (0=combinational, 1=pipelined) (default: 0)",
    )

    args = parser.parse_args()

    if args.exhaustive and args.width <= 4:
        args.num_tests = 2 ** (3 * args.width)

    generate_test_data(
        width=args.width,
        num_tests=args.num_tests,
        exhaustive=args.exhaustive,
        technique=args.technique,
        output_dir=args.output
    )
    
    export_defines(args)
