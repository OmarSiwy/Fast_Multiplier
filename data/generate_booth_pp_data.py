#!/usr/bin/env python3
"""Generate test data for Booth encoder testbench"""
import random
import os


def booth_encode(y, booth_bits, width):
    """
    Compute expected Booth encoder outputs

    Args:
        y: Multiplicand value
        booth_bits: 3-bit Booth encoding {x[i+1], x[i], x[i-1]}
        width: Bit width of y

    Returns:
        (pp, cpl): Partial product and complement bit
    """
    # Sign extend y to width+1 bits
    if y & (1 << (width - 1)):  # If negative (MSB set)
        y_ext = y | (1 << width)  # Sign extend
    else:
        y_ext = y

    # Decode booth_bits
    one = booth_bits in [0b001, 0b010, 0b101, 0b110]
    two = (booth_bits == 0b011) or (booth_bits == 0b100)
    sign = (booth_bits >> 2) & 1  # MSB of booth_bits

    # Shift for 2x
    y_shifted = (y_ext << 1) & ((1 << (width + 1)) - 1)

    # 2:1 Mux: select between 1y and 2y
    selected = y_shifted if two else y_ext if one else 0

    # XOR for conditional negation
    # XOR with all 1s if sign bit is set (one's complement)
    if sign:
        pp = selected ^ ((1 << (width + 1)) - 1)
    else:
        pp = selected

    # Mask to width+1 bits
    pp = pp & ((1 << (width + 1)) - 1)

    # Complement bit: needed when we negate (to complete two's complement)
    cpl = sign

    return pp, cpl


def generate_test_data(num_tests=32, width=16, output_dir="data/"):
    """
    Generate random test vectors for Booth encoder

    Args:
        num_tests: Number of test cases
        width: Bit width of multiplicand y
    """
    y_vals = []
    booth_bits_vals = []
    pp_vals = []
    cpl_vals = []

    # Add corner cases
    corner_cases = [
        # (y, booth_bits, description)
        (0, 0b000, "Zero × Zero"),
        (0, 0b111, "Zero × Zero (111)"),
        ((1 << width) - 1, 0b001, "All 1s × +1"),
        ((1 << width) - 1, 0b011, "All 1s × +2"),
        ((1 << width) - 1, 0b101, "All 1s × -1"),
        ((1 << width) - 1, 0b100, "All 1s × -2"),
        (1, 0b001, "1 × +1"),
        (1, 0b011, "1 × +2"),
        (1, 0b101, "1 × -1"),
        (1, 0b100, "1 × -2"),
        ((1 << (width - 1)), 0b001, "MSB set × +1"),
        ((1 << (width - 1)), 0b101, "MSB set × -1"),
    ]

    # Generate test cases
    for i in range(num_tests - len(corner_cases)):
        # Random multiplicand (full width including negative numbers)
        y = random.randint(0, (1 << width) - 1)

        # Random booth bits (3 bits: 0-7)
        booth_bits = random.randint(0, 7)

        # Calculate expected outputs
        pp, cpl = booth_encode(y, booth_bits, width)

        y_vals.append(y)
        booth_bits_vals.append(booth_bits)
        pp_vals.append(pp)
        cpl_vals.append(cpl)

    for y, booth_bits, desc in corner_cases:
        pp, cpl = booth_encode(y, booth_bits, width)
        y_vals.append(y)
        booth_bits_vals.append(booth_bits)
        pp_vals.append(pp)
        cpl_vals.append(cpl)

    def write_hex(filename, values, format_spec="x"):
        path = os.path.join(output_dir, filename)
        with open(path, "w") as f:
            for val in values:
                f.write(f"{val:{format_spec}}\n")

    write_hex("y.hex", y_vals)
    write_hex("booth_bits.hex", booth_bits_vals, "01x")
    write_hex("pp.hex", pp_vals)
    write_hex("cpl.hex", cpl_vals)

    # Print summary
    total_tests = len(y_vals)
    print(f"Generated {total_tests} test vectors ({width}-bit width)")
    print(f"  - {num_tests-len(corner_cases)} random tests")
    print(f"  - {len(corner_cases)} corner cases")
    print(f"\nFiles written: y.hex, booth_bits.hex, pp.hex, cpl.hex")

    # Booth encoding legend
    print("\nBooth Radix-4 Encoding:")
    print("  000, 111 → ×0")
    print("  001, 010 → ×(+1)")
    print("  011      → ×(+2)")
    print("  100      → ×(-2)")
    print("  101, 110 → ×(-1)")

    print("\nSample test cases:")
    for i in range(min(5, total_tests)):
        booth_str = f"{booth_bits_vals[i]:03b}"
        # Decode operation
        if booth_bits_vals[i] in [0b000, 0b111]:
            op = "×0"
        elif booth_bits_vals[i] in [0b001, 0b010]:
            op = "×(+1)"
        elif booth_bits_vals[i] == 0b011:
            op = "×(+2)"
        elif booth_bits_vals[i] == 0b100:
            op = "×(-2)"
        elif booth_bits_vals[i] in [0b101, 0b110]:
            op = "×(-1)"
        else:
            op = "×?"

        print(
            f"  Test {i}: y={y_vals[i]:04x}, booth={booth_str} {op} → pp={pp_vals[i]:05x}, cpl={cpl_vals[i]}"
        )


def export_defines(args):
    # generate tb/top.h
    # Create output directory if needed
    os.makedirs(args.header, exist_ok=True)
    header_path = os.path.join(args.header, "top.h")

    with open(header_path, "w") as f:
        f.write(f"`define W {args.width}\n")
        f.write(f"`define TESTS {args.num_tests}\n")

    print(f"Header file written to: {header_path}")


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="Generate Booth encoder test data")
    parser.add_argument(
        "-n",
        "--num-tests",
        type=int,
        default=40,
        help="Number of random test cases (default: 16)",
    )
    parser.add_argument(
        "-w",
        "--width",
        type=int,
        default=16,
        help="Bit width of multiplicand (default: 16)",
    )
    parser.add_argument(
        "-o",
        "--output",
        type=str,
        default="data/",
        help="Output directory (default: current folder)",
    )
    parser.add_argument(
        "-r",
        "--header",
        type=str,
        default="tb/",
        help="Output directory to store top.h header file",
    )

    args = parser.parse_args()

    generate_test_data(args.num_tests, args.width, args.output)
    export_defines(args)
