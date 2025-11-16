#!/usr/bin/env python3
"""Generate test data for multiplier testbench"""

import random
import os


def twos_complement(value, bits):
    """Compute the two's complement of int value given number of bits."""
    if value & (1 << (bits - 1)):  # if most significant bit is set
        value -= 1 << bits  # subtract 2^bits to get negative value
    return value


def twos_from_signed(value, bits):
    """Convert signed int to two's complement representation given number of bits."""
    if value < 0:
        value += 1 << bits
    return value


def generate_test_data(args):
    """
    Generate test vectors for multiplier

    Args:
        num_tests: Number of test cases
        width: Bit width of operands
        output_dir: Directory to write output hex files
    """
    signed = not (args.unsigned)
    width = args.width
    num_tests = args.num_tests
    output_dir = args.output
    exhaustive = args.exhaustive
    os.makedirs(output_dir, exist_ok=True)

    a_vals = []
    b_vals = []
    p_vals = []
    if exhaustive:
        max_val = 1 << width
        print(f"Running exhaustive generation for width={width} ...")

        for a in range(max_val):
            for b in range(max_val):
                if signed:
                    a_signed = twos_complement(a, width)
                    b_signed = twos_complement(b, width)
                    p_signed = a_signed * b_signed
                    p = twos_from_signed(p_signed, 2 * width)
                else:
                    p = a * b

                a_vals.append(a)
                b_vals.append(b)
                p_vals.append(p)
        num_tests = len(a_vals)
    else:
        for _ in range(num_tests):
            if signed:
                a = random.randint(-(1 << (width - 1)), (1 << (width - 1)) - 1)
                b = random.randint(-(1 << (width - 1)), (1 << (width - 1)) - 1)
                a_hex = twos_from_signed(a, width)
                b_hex = twos_from_signed(b, width)
            else:
                a_hex = random.randint(0, (1 << width) - 1)
                b_hex = random.randint(0, (1 << width) - 1)
                a = a_hex
                b = b_hex
            p = a * b
            p_hex = p & ((1 << (2 * width)) - 1)

            a_vals.append(a_hex)
            b_vals.append(b_hex)
            p_vals.append(p_hex)

    # Write to files
    def write_hex(filename, values):
        path = os.path.join(output_dir, filename)
        with open(path, "w") as f:
            for val in values:
                f.write(f"{val:x}\n")

    write_hex("a_vals.hex", a_vals)
    write_hex("b_vals.hex", b_vals)
    write_hex("p_vals.hex", p_vals)

    print(f"Generated {num_tests} test vectors ({width}-bit)")
    print(f"Files written to: {os.path.abspath(output_dir)}")
    print("\nSample test cases:")
    if args.dump_all:
        for i in range(num_tests):
            print(f"  Test {i}: {a_vals[i]:x} * {b_vals[i]:x} = {p_vals[i]:x}")
            if signed:
                print(
                    f"            {twos_complement(a_vals[i], width)} * {twos_complement(b_vals[i], width)} = {twos_complement(p_vals[i], 2 * width)}"
                )  # want 2s complement decimal values
            else:
                print(f"            {a_vals[i]} * {b_vals[i]} = {p_vals[i]}")
    else:
        for i in range(min(3, num_tests)):
            print(f"  Test {i}: {a_vals[i]:x} * {b_vals[i]:x} = {p_vals[i]:x}")
            if signed:
                print(
                    f"            {twos_complement(a_vals[i], width)} * {twos_complement(b_vals[i], width)} = {twos_complement(p_vals[i], 2 * width)}"
                )  # want 2s complement decimal values
            else:
                print(f"            {a_vals[i]} * {b_vals[i]} = {p_vals[i]}")


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="Generate adder test data")
    parser.add_argument(
        "-n",
        "--num-tests",
        type=int,
        default=8,
        help="Number of test cases (ignored in exhaustive mode)",
    )
    parser.add_argument(
        "-w", "--width", type=int, default=16, help="Bit width of operands"
    )
    parser.add_argument(
        "-u",
        "--unsigned",
        action="store_true",
        default=True,
        help="Generate unsigned multiplication test vectors",
    )
    parser.add_argument(
        "-o", "--output", type=str, default=".", help="Output directory for hex files"
    )
    parser.add_argument(
        "--exhaustive",
        action="store_true",
        help="Generate all possible input combinations (only valid for width ≤ 4)",
    )
    parser.add_argument(
        "--dump_all",
        action="store_true",
        help="Dump all generated test vectors to console",
    )
    parser.add_argument(
        "--no-random",
        action="store_true",
        help="Disable random seed for reproducibility",
    )

    args = parser.parse_args()
    if args.no_random:
        random.seed(0)

    if args.exhaustive:
        max_width = 16
        if args.width > max_width:
            raise ValueError(f"Exhaustive mode only valid for width ≤ {max_width}")
        num_tests = 2 ** (args.width * 2)
        args.num_tests = num_tests

    generate_test_data(args)
