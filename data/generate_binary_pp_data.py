#!/usr/bin/env python3
"""Generate test data for Binary partial product generator testbench"""
import random
import os

def binary_pp_compute(y, binary_bit, width):
    """
    Compute expected binary partial product output

    Args:
        y: Multiplicand value
        binary_bit: Single bit multiplier bit (0 or 1)
        width: Bit width of y

    Returns:
        pp: Partial product (width+1 bits)
    """
    # Sign extend y to width+1 bits
    if y & (1 << (width-1)):  # If negative (MSB set)
        y_ext = y | (1 << width)  # Sign extend
    else:
        y_ext = y & ((1 << width) - 1)  # Mask to width bits, then no sign extension needed

    # Generate partial product
    if binary_bit:
        pp = y_ext
    else:
        pp = 0

    # Mask to width+1 bits
    pp = pp & ((1 << (width+1)) - 1)

    return pp


def generate_test_data(num_tests=32, width=16, output_dir="data/"):
    """
    Generate test vectors for binary partial product generator

    Args:
        num_tests: Number of random test cases
        width: Bit width of multiplicand y
    """
    y_vals = []
    binary_bit_vals = []
    pp_vals = []

    # Add comprehensive corner cases
    corner_cases = [
        # (y, binary_bit, description)
        # Basic cases
        (0, 0, "Zero × 0"),
        (0, 1, "Zero × 1"),
        (1, 0, "One × 0"),
        (1, 1, "One × 1"),

        # Maximum positive value (for signed interpretation: 0x7FFF = 32767)
        ((1 << (width-1)) - 1, 0, "Max positive × 0"),
        ((1 << (width-1)) - 1, 1, "Max positive × 1"),

        # Minimum negative value (for signed interpretation: 0x8000 = -32768)
        (1 << (width-1), 0, "Min negative (MSB) × 0"),
        (1 << (width-1), 1, "Min negative (MSB) × 1"),

        # All ones (represents -1 in two's complement)
        ((1 << width) - 1, 0, "All ones (-1) × 0"),
        ((1 << width) - 1, 1, "All ones (-1) × 1"),

        # Alternating patterns
        (0x5555, 0, "Pattern 0x5555 × 0"),
        (0x5555, 1, "Pattern 0x5555 × 1"),
        (0xAAAA, 0, "Pattern 0xAAAA × 0"),
        (0xAAAA, 1, "Pattern 0xAAAA × 1"),

        # Small positive and negative values
        (2, 1, "Two × 1"),
        (3, 1, "Three × 1"),
        ((1 << width) - 2, 1, "-2 (0xFFFE) × 1"),
        ((1 << width) - 3, 1, "-3 (0xFFFD) × 1"),

        # Powers of 2
        (0x0010, 1, "16 (0x0010) × 1"),
        (0x0100, 1, "256 (0x0100) × 1"),
        (0x1000, 1, "4096 (0x1000) × 1"),
        (0x4000, 1, "16384 (0x4000) × 1"),
    ]

    # Generate random test cases
    for i in range(num_tests-len(corner_cases)):
        # Random multiplicand (full width including negative numbers)
        y = random.randint(0, (1 << width) - 1)

        # Random binary bit (0 or 1)
        binary_bit = random.randint(0, 1)

        # Calculate expected output
        pp = binary_pp_compute(y, binary_bit, width)

        y_vals.append(y)
        binary_bit_vals.append(binary_bit)
        pp_vals.append(pp)


    # Add corner cases to the test vectors
    for y, binary_bit, desc in corner_cases:
        pp = binary_pp_compute(y, binary_bit, width)
        y_vals.append(y)
        binary_bit_vals.append(binary_bit)
        pp_vals.append(pp)

    def write_hex(filename, values, format_spec='x'):
        path = os.path.join(output_dir, filename)
        with open(path, 'w') as f:
            for val in values:
                f.write(f'{val:{format_spec}}\n')

    write_hex('y.hex', y_vals)
    write_hex('binary_bit.hex', binary_bit_vals, '01x')
    write_hex('pp.hex',pp_vals)

    # Print summary
    total_tests = len(y_vals)
    print(f"Generated {total_tests} test vectors ({width}-bit width)")
    print(f"  - {num_tests-len(corner_cases)} random tests")
    print(f"  - {len(corner_cases)} corner cases")
    print(f"\nFiles written: y.hex, binary_bit.hex, pp.hex")

    # Binary multiplication legend
    print("\nBinary Multiplication:")
    print("  bit = 0 → pp = 0")
    print("  bit = 1 → pp = sign_extend(y)")

    print("\nSample test cases:")
    for i in range(min(10, total_tests)):
        # Interpret y as signed for display
        y_signed = y_vals[i] if y_vals[i] < (1 << (width-1)) else y_vals[i] - (1 << width)
        pp_signed = pp_vals[i] if pp_vals[i] < (1 << width) else pp_vals[i] - (1 << (width+1))

        print(f"  Test {i:2d}: y=0x{y_vals[i]:04x} ({y_signed:6d}), "
              f"bit={binary_bit_vals[i]} → "
              f"pp=0x{pp_vals[i]:05x} ({pp_signed:6d})")

    # Verify a few calculations manually
    print("\nVerification of sign extension:")
    test_cases = [
        (0x0001, 1),  # Positive small
        (0x7FFF, 1),  # Maximum positive
        (0x8000, 1),  # Minimum negative
        (0xFFFF, 1),  # -1
    ]

    for y, bit in test_cases:
        pp = binary_pp_compute(y, bit, width)
        y_signed = y if y < (1 << (width-1)) else y - (1 << width)
        pp_signed = pp if pp < (1 << width) else pp - (1 << (width+1))
        print(f"  y=0x{y:04x} ({y_signed:6d}) × {bit} → pp=0x{pp:05x} ({pp_signed:6d})")

def export_defines(args):
    # generate tb/top.h
    # Create output directory if needed
    os.makedirs(args.header, exist_ok=True)
    header_path = os.path.join(args.header, "top.h")

    with open(header_path, "w") as f:
        f.write(f"`define W {args.width}\n")
        f.write(f"`define TESTS {args.num_tests}\n")


if __name__ == '__main__':
    import argparse

    parser = argparse.ArgumentParser(description='Generate binary partial product test data')
    parser.add_argument('-n', '--num-tests', type=int, default=40,
                        help='Number of random test cases (default: 40)')
    parser.add_argument('-w', '--width', type=int, default=16,
                        help='Bit width of multiplicand (default: 16)')
    parser.add_argument('-s', '--seed', type=int, default=None,
                        help='Random seed for reproducible tests')
    parser.add_argument('-o', '--output', type=str, default='data/',
                        help='Output directory (default: current folder)')
    parser.add_argument('-r','--header', type=str, default='tb/',
                        help='Output directory to store top.h header file')

    args = parser.parse_args()

    if args.seed is not None:
        random.seed(args.seed)
        print(f"Using random seed: {args.seed}")

    generate_test_data(args.num_tests, args.width, args.output)
    export_defines(args)
