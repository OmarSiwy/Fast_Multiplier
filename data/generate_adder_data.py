#!/usr/bin/env python3
"""Generate test data for adder testbench"""

import random
import os

def generate_test_data(num_tests=8, width=32, exhaustive=False, output_dir="."):
    """
    Generate test vectors for adder

    Args:
        num_tests: Number of test cases (ignored in exhaustive mode)
        width: Bit width of operands
        exhaustive: If True, generate all possible input combinations (for small widths)
        output_dir: Directory to write output hex files
        header: If True, also generate tb/top.h with defines
    """

    os.makedirs(output_dir, exist_ok=True)

    a_vals = []
    b_vals = []
    c_in_vals = []
    s_vals = []
    c_out_vals = []

    if exhaustive:
        max_val = 1 << width
        print(f"Running exhaustive generation for width={width} ...")
        if width > 8:
            raise ValueError("Exhaustive mode only allowed for width ≤ 8 (too large otherwise).")

        for a in range(max_val):
            for b in range(max_val):
                for c_in in (0, 1):
                    if c_in == 1:
                        # Subtraction mode: a - b
                        # In hardware: a + ~b + 1
                        b_inverted = ((1 << width) - 1) ^ b  # Bitwise NOT of b
                        result = a + b_inverted + 1
                    else:
                        # Addition mode: a + b
                        result = a + b

                    s = result & ((1 << width) - 1)
                    c_out = (result >> width) & 1

                    a_vals.append(a)
                    b_vals.append(b)
                    c_in_vals.append(c_in)
                    s_vals.append(s)
                    c_out_vals.append(c_out)
        num_tests = len(a_vals)

    else:
        for _ in range(num_tests):
            a = random.randint(0, (1 << width) - 1)
            b = random.randint(0, (1 << width) - 1)
            c_in = random.randint(0, 1)

            if c_in == 1:
                # Subtraction mode: a - b
                # In hardware: a + ~b + 1
                b_inverted = ((1 << width) - 1) ^ b  # Bitwise NOT of b
                result = a + b_inverted + 1
            else:
                # Addition mode: a + b
                result = a + b

            s = result & ((1 << width) - 1)
            c_out = (result >> width) & 1

            a_vals.append(a)
            b_vals.append(b)
            c_in_vals.append(c_in)
            s_vals.append(s)
            c_out_vals.append(c_out)

    # Write hex files
    def write_hex(filename, values):
        path = os.path.join(output_dir, filename)
        with open(path, 'w') as f:
            for val in values:
                f.write(f'{val:x}\n')

    write_hex('a.hex', a_vals)
    write_hex('b.hex', b_vals)
    write_hex('c_in.hex', c_in_vals)
    write_hex('s.hex', s_vals)
    write_hex('c_out.hex', c_out_vals)

    # Print summary
    print(f"Generated {num_tests} test vectors ({width}-bit)")
    print(f"Files written to: {os.path.abspath(output_dir)}")
    print("\nSample test cases:")
    for i in range(min(3, num_tests)):
        print(f"  Test {i}: {a_vals[i]:x} + {b_vals[i]:x} + {c_in_vals[i]} = {c_out_vals[i]}{s_vals[i]:x}")


def export_defines(args):
    # generate tb/top.h
    # Create output directory if needed
    os.makedirs(args.header, exist_ok=True)
    header_path = os.path.join(args.header, "top.h")

    with open(header_path, "w") as f:
        f.write(f"`define W {args.width}\n")
        f.write(f"`define M {args.mchunk}\n")
        f.write(f"`define TESTS {args.num_tests}\n")

    print(f"Header file written to: {header_path}")


if __name__ == '__main__':
    import argparse

    parser = argparse.ArgumentParser(description='Generate adder test data')
    parser.add_argument('-n', '--num-tests', type=int, default=8,
                        help='Number of test cases (ignored in exhaustive mode)')
    parser.add_argument('-w', '--width', type=int, default=32,
                        help='Bit width (default: 32)')
    parser.add_argument('-m', '--mchunk', type=int, default=4,
                        help='Chunk width (default: 4)')
    parser.add_argument('--exhaustive', action='store_true',
                        help='Generate all possible input combinations (only valid for width ≤ 8)')
    parser.add_argument('-o', '--output', type=str, default='data/',
                        help='Output directory (default: current folder)')
    parser.add_argument('-r','--header', type=str, default='tb/',
                        help='Output directory to store top.h header file')
    parser.add_argument('--no-random', action='store_true',
                        help='Disable random seed for reproducibility')

    args = parser.parse_args()

    if args.exhaustive:
        args.num_tests = 2 ** (args.width * 2 + 1)

    if args.no_random:
        random.seed(0)

    generate_test_data(args.num_tests, args.width, args.exhaustive, args.output)
    export_defines(args);
