#!/usr/bin/env python3
"""Generate test data for prefix_cell.sv"""

import random
import os

def generate_test_data(num_tests=64, exhaustive=False, output_dir="./data"):
    """
    Generate random or exhaustive test vectors for prefix_cell.sv

    Args:
        num_tests: Number of random test cases (ignored if exhaustive=True)
        exhaustive: If True, generate all 64 possible input combinations
    """

    os.makedirs(output_dir, exist_ok=True)

    g_hi_vals, p_hi_vals, a_hi_vals = [], [], []
    g_lo_vals, p_lo_vals, a_lo_vals = [], [], []
    g_out_vals, p_out_vals, a_out_vals = [], [], []

    def prefix_cell(g_hi, p_hi, a_hi, g_lo, p_lo, a_lo):
        """Compute expected outputs for prefix_cell"""
        g_out = g_hi | (p_hi & g_lo)
        p_out = p_hi & p_lo
        a_out = a_hi | (p_hi & a_lo)
        return g_out, p_out, a_out

    if exhaustive:
        inputs = [(g_hi, p_hi, a_hi, g_lo, p_lo, a_lo)
                  for g_hi in (0, 1)
                  for p_hi in (0, 1)
                  for a_hi in (0, 1)
                  for g_lo in (0, 1)
                  for p_lo in (0, 1)
                  for a_lo in (0, 1)]
    else:
        inputs = [(random.randint(0, 1),
                   random.randint(0, 1),
                   random.randint(0, 1),
                   random.randint(0, 1),
                   random.randint(0, 1),
                   random.randint(0, 1))
                  for _ in range(num_tests)]

    for (g_hi, p_hi, a_hi, g_lo, p_lo, a_lo) in inputs:
        g_out, p_out, a_out = prefix_cell(g_hi, p_hi, a_hi, g_lo, p_lo, a_lo)

        g_hi_vals.append(g_hi)
        p_hi_vals.append(p_hi)
        a_hi_vals.append(a_hi)
        g_lo_vals.append(g_lo)
        p_lo_vals.append(p_lo)
        a_lo_vals.append(a_lo)
        g_out_vals.append(g_out)
        p_out_vals.append(p_out)
        a_out_vals.append(a_out)

    # Write to hex files
    def write_hex(filename, values):
        path = os.path.join(output_dir, filename)
        with open(path, 'w') as f:
            for val in values:
                f.write(f'{val:x}\n')


    write_hex('g_hi.hex', g_hi_vals)
    write_hex('p_hi.hex', p_hi_vals)
    write_hex('a_hi.hex', a_hi_vals)
    write_hex('g_lo.hex', g_lo_vals)
    write_hex('p_lo.hex', p_lo_vals)
    write_hex('a_lo.hex', a_lo_vals)
    write_hex('g_out.hex', g_out_vals)
    write_hex('p_out.hex', p_out_vals)
    write_hex('a_out.hex', a_out_vals)

    print(f"Generated {len(inputs)} test vectors for prefix_cell")
    print(f"Files written to current directory\n")
    for i in range(min(5, len(inputs))):
        print(f"Test {i}: "
              f"g_hi={g_hi_vals[i]} p_hi={p_hi_vals[i]} a_hi={a_hi_vals[i]} | "
              f"g_lo={g_lo_vals[i]} p_lo={p_lo_vals[i]} a_lo={a_lo_vals[i]} -> "
              f"g_out={g_out_vals[i]} p_out={p_out_vals[i]} a_out={a_out_vals[i]}")

def export_defines(args):
    # generate tb/top.h
    # Create output directory if needed
    os.makedirs(args.header, exist_ok=True)
    header_path = os.path.join(args.header, "top.h")

    with open(header_path, "w") as f:
        f.write(f"`define TESTS {args.num_tests}\n")

    print(f"Header file written to: {header_path}")

if __name__ == '__main__':
    import argparse

    parser = argparse.ArgumentParser(description='Generate prefix_cell test data')
    parser.add_argument('-n', '--num-tests', type=int, default=64,
                        help='Number of test cases (default: 64)')
    parser.add_argument('-e', '--exhaustive', action='store_true',
                        help='Generate all 64 input combinations')
    parser.add_argument('-o', '--output', type=str, default='data/',
                        help='Output directory (default: current folder)')
    parser.add_argument('-r','--header', type=str, default='tb/',
                        help='Output directory to store top.h header file')

    args = parser.parse_args()

    if args.exhaustive:
        args.num_tests = 2 ** (6)

    generate_test_data(args.num_tests, args.exhaustive, args.output)
    export_defines(args)

