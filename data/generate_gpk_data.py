#!/usr/bin/env python3
"""Generate test data for gpk.sv"""

import random
import os


def generate_test_data(num_tests=16, exhaustive=False, output_dir="./data"):
    """
    Generate random or exhaustive test vectors for gpk.sv

    Args:
        num_tests: Number of random test cases (ignored if exhaustive=True)
        exhaustive: If True, generate all 4 possible input combinations
    """

    os.makedirs(output_dir, exist_ok=True)

    a_vals, b_vals = [], []
    g_vals, p_vals, k_vals = [], [], []

    def gpk(a, b):
        """Compute expected outputs for gpk"""
        g = a & b  # generate: both inputs are 1
        p = a ^ b  # propagate: inputs are different
        k = (1 - a) & (1 - b)  # kill: both inputs are 0
        return g, p, k

    if exhaustive:
        inputs = [(a, b) for a in (0, 1) for b in (0, 1)]
    else:
        inputs = [
            (random.randint(0, 1), random.randint(0, 1)) for _ in range(num_tests)
        ]

    for a, b in inputs:
        g, p, k = gpk(a, b)

        a_vals.append(a)
        b_vals.append(b)
        g_vals.append(g)
        p_vals.append(p)
        k_vals.append(k)

    # Write to hex files
    def write_hex(filename, values):
        path = os.path.join(output_dir, filename)
        with open(path, "w") as f:
            for val in values:
                f.write(f"{val:x}\n")

    write_hex("a.hex", a_vals)
    write_hex("b.hex", b_vals)
    write_hex("g.hex", g_vals)
    write_hex("p.hex", p_vals)
    write_hex("k.hex", k_vals)

    print(f"Generated {len(inputs)} test vectors for gpk")
    print(f"Files written to {output_dir}\n")
    for i in range(min(5, len(inputs))):
        print(
            f"Test {i}: "
            f"a={a_vals[i]} b={b_vals[i]} -> "
            f"g={g_vals[i]} p={p_vals[i]} k={k_vals[i]}"
        )


def export_defines(args):
    # generate tb/top.h
    # Create output directory if needed
    os.makedirs(args.header, exist_ok=True)
    header_path = os.path.join(args.header, "top.h")

    with open(header_path, "w") as f:
        f.write(f"`define TESTS {args.num_tests}\n")

    print(f"Header file written to: {header_path}")


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="Generate gpk test data")
    parser.add_argument(
        "-n",
        "--num-tests",
        type=int,
        default=16,
        help="Number of test cases (default: 16)",
    )
    parser.add_argument(
        "-e",
        "--exhaustive",
        action="store_true",
        help="Generate all 4 input combinations",
    )
    parser.add_argument(
        "-o",
        "--output",
        type=str,
        default="data/",
        help="Output directory (default: data/)",
    )
    parser.add_argument(
        "-r",
        "--header",
        type=str,
        default="tb/",
        help="Output directory to store top.h header file",
    )

    args = parser.parse_args()

    if args.exhaustive:
        args.num_tests = 2**2  # 4 combinations for 2 inputs

    generate_test_data(args.num_tests, args.exhaustive, args.output)
    export_defines(args)
