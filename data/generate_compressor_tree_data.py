#!/usr/bin/env python3
"""
Generate test vectors (partial products) for compressor_tree.sv testbench
"""

import random
import argparse
import os
import sys


def uint_to_signed(val, w):
    """Convert an unsigned integer to signed integer with width w"""
    if val >= (1 << (w - 1)):
        val -= 1 << w
    return val


def uint_to_binary_str(val, w):
    """Convert an unsigned integer to a binary string with width w"""
    return format(val, f"#0{w}b")


def sign_extend(val, from_w, to_w):
    """Sign-extend a value from from_w to to_w bits"""
    sign_bit = (val >> (from_w - 1)) & 1
    if sign_bit:
        extension = ((1 << (to_w - from_w)) - 1) << from_w
        return val | extension
    else:
        return val & ((1 << to_w) - 1)


# -------------------------------------------------------------------------
#  Booth‑radix‑4 partial‑product generator
# -------------------------------------------------------------------------
def booth_radix4_pp_unsigned(a, b, w):
    """Generate Unsigned Booth Radix-4 partial products for a * b"""
    b_bits = [(b >> i) & 1 for i in range(w)]
    b_ext = [0] + b_bits + [0] + [0]  # zero-extend for unsigned
    mask = (1 << (w + 1)) - 1  # keep w+1 bits for sign-extended PPs
    print(f"a: {a}, b: {b}, w: {w}")
    print(f"a(bin): {uint_to_binary_str(a, w)}, b(bin): {uint_to_binary_str(b, w)}")
    print(f"b_ext: {b_ext[::-1]}, mask: {mask:#0{w}b}")
    partial_products = []
    cpl_bits = []

    num_pp = (w) // 2 + 1

    for i in range(1, num_pp + 1):
        idx = i * 2 - 1
        b0 = b_ext[idx - 1]
        b1 = b_ext[idx]
        b2 = b_ext[idx + 1]

        print(f"    PP {i}: b2={b2}, b1={b1}, b0={b0}")
        encoding = (b2 << 2) | (b1 << 1) | b0
        encoding_str = ""
        if encoding == 0:
            pp, cpl = 0, 0  # 0
            encoding_str = "+0"
        elif encoding == 1 or encoding == 2:
            # +1
            encoding_str = "+1"
            cpl = 0
            pp = sign_extend(a, w, w + 1) & mask
        elif encoding == 3:
            # +2
            encoding_str = "+2"
            cpl = 0
            pp = (2 * a) & mask
        elif encoding == 4:
            # -2
            encoding_str = "-2"
            cpl = 1
            pp = (~(2 * a)) & mask
        elif encoding == 5 or encoding == 6:
            # -1
            encoding_str = "-1"
            cpl = 1
            pp = (~sign_extend(a, w, w + 1)) & mask
        else:  # encoding == 7
            # 0
            encoding_str = "-0"
            pp, cpl = mask, 1  # 0

        partial_products.append(pp & mask)
        if i < num_pp:
            print(f"        encoding: {encoding_str}, pp: {pp:#0{2*w-1}b}, cpl: {cpl}")
            cpl_bits.append(cpl)
        else:
            print(f"        encoding: {encoding_str}, pp: {pp:#0{2*w-1}b} (no cpl)")

    return partial_products, cpl_bits


def booth_radix4_pp_signed(a, b, w):
    """Generate Signed Booth Radix-4 partial products for a * b"""
    b_bits = [(b >> i) & 1 for i in range(w)]
    b_ext = [0] + b_bits + [b_bits[w - 1]]
    mask = (1 << (w + 1)) - 1  # keep w+1 bits for sign-extended PPs
    print(f"a: {uint_to_signed(a, w)}, b: {uint_to_signed(b, w)}, w: {w}")
    print(f"a(bin): {uint_to_binary_str(a, w)}, b(bin): {uint_to_binary_str(b, w)}")
    print(f"b_ext: {b_ext[::-1]}, mask: {mask:#0{w}b}")
    partial_products = []
    cpl_bits = []

    num_pp = (w + 1) // 2

    for i in range(1, num_pp + 1):
        idx = i * 2 - 1
        b0 = b_ext[idx - 1]
        b1 = b_ext[idx]
        b2 = b_ext[idx + 1]

        print(f"    PP {i}: b2={b2}, b1={b1}, b0={b0}")
        encoding = (b2 << 2) | (b1 << 1) | b0
        encoding_str = ""
        if encoding == 0:
            pp, cpl = 0, 0  # 0
            encoding_str = "+0"
        elif encoding == 1 or encoding == 2:
            # +1
            encoding_str = "+1"
            cpl = 0
            pp = sign_extend(a, w, w + 1) & mask
        elif encoding == 3:
            # +2
            encoding_str = "+2"
            cpl = 0
            pp = (2 * a) & mask
        elif encoding == 4:
            # -2
            encoding_str = "-2"
            cpl = 1
            pp = (~(2 * a)) & mask
        elif encoding == 5 or encoding == 6:
            # -1
            encoding_str = "-1"
            cpl = 1
            pp = (~sign_extend(a, w, w + 1)) & mask
        else:  # encoding == 7
            # 0
            encoding_str = "-0"
            pp, cpl = mask, 1  # 0

        print(f"        encoding: {encoding_str}, pp: {pp:#0{2*w-1}b}, cpl: {cpl}")
        partial_products.append(pp & mask)
        cpl_bits.append(cpl)

    return partial_products, cpl_bits


# -------------------------------------------------------------------------
#  Binary radix‑2 unsigned partial‑product generator
# -------------------------------------------------------------------------
def binary_radix2_unsigned_pp(a, b, w):
    """Generate binary radix-2 unsigned partial products for a * b"""
    partial_products = []
    prod_width = 2 * w
    mask = (1 << prod_width) - 1  # keep only prod_width bits

    for i in range(w):
        b_bit = (b >> i) & 1
        pp = (a & mask) if b_bit else 0
        # remove shift!
        # pp = (a << i) & ((1 << prod_width) - 1) if b_bit else 0
        partial_products.append(pp)

    return partial_products, None


# -------------------------------------------------------------------------
#  Binary radix‑2 signed partial‑product generator (Baugh‑Wooley)
# -------------------------------------------------------------------------
def binary_radix2_signed_pp(a, b, w):
    return binary_radix2_unsigned_pp(a, b, w)
    # """Generate binary radix-2 signed partial products using Baugh-Wooley"""
    # partial_products = []
    # prod_width = 2 * w

    # for i in range(w):
    #     b_bit = (b >> i) & 1
    #     if i < w - 1:
    #         pp = (a << i) & ((1 << prod_width) - 1) if b_bit else 0
    #     else:
    #         pp = ((~a) << i) & ((1 << prod_width) - 1) if b_bit else 0
    #     partial_products.append(pp)

    # return partial_products, None


# -------------------------------------------------------------------------
#  Main vector‑generation routine
# -------------------------------------------------------------------------
def generate_test_vectors(
    w,
    encoding,
    unsigned,
    output_dir,
    num_tests=8,
    exhaustive=False,
):
    """Generate partial product test vectors"""

    os.makedirs(output_dir, exist_ok=True)

    # -----------------------------------------------------------------
    # 1️⃣  Build the list of operand pairs (a,b)
    # -----------------------------------------------------------------
    if exhaustive:
        # Guard against ridiculously large files.
        MAX_EXHAUSTIVE = 2**20  # ~1 M vectors → ~16 MiB for 16‑bit operands
        total_vectors = (1 << w) * (1 << w)
        if total_vectors > MAX_EXHAUSTIVE:
            print(
                f"⚠️  Exhaustive mode would create {total_vectors:,} test vectors,\n"
                f"   which exceeds the safety limit of {MAX_EXHAUSTIVE:,}.\n"
                f"   Reduce the operand width or remove '--exhaustive'.",
                file=sys.stderr,
            )
            sys.exit(1)

        test_a = []
        test_b = []
        for a in range(1 << w):
            for b in range(1 << w):
                test_a.append(a)
                test_b.append(b)
    else:
        # Non‑exhaustive – keep the original “hand‑picked + random” behaviour.
        test_a, test_b = [], []
        test_a.append(0)
        test_b.append(0)
        test_a.append((1 << w) - 1)
        test_b.append((1 << w) - 1)

        if not unsigned:
            test_a += [1 << (w - 1), 1, (1 << (w - 1)) - 1]
            test_b += [1, 1 << (w - 1), (1 << (w - 1)) - 1]
        else:
            test_a += [1, (1 << w) - 1]
            test_b += [1, 1]

        # Fill the remainder with random values up to the requested count.
        for _ in range(num_tests - len(test_a)):
            test_a.append(random.randint(0, (1 << w) - 1))
            test_b.append(random.randint(0, (1 << w) - 1))

    # -----------------------------------------------------------------
    # 2️⃣  Choose the PP generator
    # -----------------------------------------------------------------
    if encoding == "booth":
        if unsigned:
            pp_gen = booth_radix4_pp_unsigned
            num_pp = (w) // 2 + 1
            num_cpl = (w) // 2
        else:
            pp_gen = booth_radix4_pp_signed
            num_cpl = (w + 1) // 2
            num_pp = (w + 1) // 2
    else:
        num_pp = w
        pp_gen = binary_radix2_unsigned_pp if unsigned else binary_radix2_signed_pp

    prod_width = 2 * w
    all_pps, all_cpls, expected = [], [], []

    # -----------------------------------------------------------------
    # 3️⃣  Generate PP, CPL (if any) and expected product for every pair
    # -----------------------------------------------------------------
    for a, b in zip(test_a, test_b):
        pps, cpls = pp_gen(a, b, w)
        all_pps.append(pps)
        all_cpls.append(cpls if cpls else [0] * num_pp)
        if unsigned:
            product = a * b
        else:
            a_signed = a if a < (1 << (w - 1)) else a - (1 << w)
            b_signed = b if b < (1 << (w - 1)) else b - (1 << w)
            product = a_signed * b_signed
            if product < 0:
                product += 1 << (2 * w)
        expected.append(product & ((1 << prod_width) - 1))

    # -----------------------------------------------------------------
    # 4️⃣  Emit the .hex files
    # -----------------------------------------------------------------
    if encoding == "booth" and unsigned:
        for pp_idx in range(num_pp):
            with open(os.path.join(output_dir, f"test_pp{pp_idx}.hex"), "w") as f:
                for test_idx in range(len(test_a)):
                    f.write(f"{all_pps[test_idx][pp_idx]:0{(prod_width + 3)//4}x}\n")
    else:
        for pp_idx in range(num_pp):
            with open(os.path.join(output_dir, f"test_pp{pp_idx}.hex"), "w") as f:
                for test_idx in range(len(test_a)):
                    f.write(f"{all_pps[test_idx][pp_idx]:0{(prod_width + 3)//4}x}\n")

    if encoding == "booth" and not unsigned:
        for cpl_idx in range(num_cpl):
            with open(os.path.join(output_dir, f"test_cpl{cpl_idx}.hex"), "w") as f:
                for test_idx in range(len(test_a)):
                    f.write(f"{all_cpls[test_idx][cpl_idx]:01x}\n")
    elif encoding == "booth" and unsigned:
        for cpl_idx in range(num_cpl):
            with open(os.path.join(output_dir, f"test_cpl{cpl_idx}.hex"), "w") as f:
                for test_idx in range(len(test_a)):
                    f.write(f"{all_cpls[test_idx][cpl_idx]:01x}\n")

    with open(os.path.join(output_dir, "test_a.hex"), "w") as f:
        for a in test_a:
            f.write(f"{a:0{(w + 3)//4}x}\n")

    with open(os.path.join(output_dir, "test_b.hex"), "w") as f:
        for b in test_b:
            f.write(f"{b:0{(w + 3)//4}x}\n")

    with open(os.path.join(output_dir, "test_expected.hex"), "w") as f:
        for exp in expected:
            f.write(f"{exp:0{(prod_width + 3)//4}x}\n")

    # -----------------------------------------------------------------
    # 5️⃣  Friendly console summary
    # -----------------------------------------------------------------
    print(f"\n✅ Test vectors written to: {output_dir}")
    print("=" * 80)
    max_display = 50  # avoid flooding the console
    for i, (a, b, exp) in enumerate(zip(test_a, test_b, expected)):
        if i >= max_display:
            print(f"... ({len(test_a) - max_display} more tests omitted)")
            break
        if unsigned:
            print(f"Test {i}: {a} * {b} = {exp}")
        else:
            print(
                f"Test {i}: {uint_to_signed(a, w)} * {uint_to_signed(b, w)} = {uint_to_signed(exp, prod_width)}"
            )
        print(
            f"        {uint_to_binary_str(a, w)} * {uint_to_binary_str(b, w)} = {uint_to_binary_str(exp, prod_width)}"
        )

    print("=" * 80)

    return test_a, test_b, all_pps, all_cpls, expected


def export_defines(args):
    """Generate Verilog `define macros based on command-line args."""
    # Compute NUM_PP and BOOTH based on encoding
    if args.encoding == "booth":
        booth = 1
        num_pp = (args.width + 1) // 2

    else:
        booth = 0
        num_pp = args.width

    # Create output directory if needed
    os.makedirs(os.path.dirname(args.header), exist_ok=True)

    header_path = os.path.join(os.path.dirname(args.header), "top.h")

    with open(header_path, "w") as f:
        f.write(f"`define W {args.width}\n")
        f.write(f"`define TESTS {args.num_tests}\n")
        f.write(f"`define NUM_PP {num_pp}\n")
        f.write(f"`define BOOTH {booth}\n")
        f.write(f"`define UNSIGNED {1 if args.unsigned else 0}\n")
        f.write(f"`define PROD_W (2*`W)\n")

    print(f"[+] Exported Verilog defines to {header_path}")


# -------------------------------------------------------------------------
#  CLI entry point
# -------------------------------------------------------------------------
def main():
    parser = argparse.ArgumentParser(
        description="Generate partial product test vectors for compressor tree"
    )
    parser.add_argument("-w", "--width", type=int, default=16, help="Input width")
    parser.add_argument(
        "-e",
        "--encoding",
        type=str,
        default="booth",
        choices=["booth", "binary"],
        help="Encoding type",
    )
    parser.add_argument(
        "--unsigned", action="store_true", help="Unsigned multiplication"
    )
    parser.add_argument(
        "-n",
        "--num-tests",
        type=int,
        default=8,
        help="Number of test vectors (ignored when --exhaustive is used)",
    )
    parser.add_argument(
        "--exhaustive",
        action="store_true",
        help="Generate *all* possible operand pairs for the given width",
    )
    parser.add_argument(
        "-o",
        "--output",
        type=str,
        default=".",
        help="Output folder for generated .hex files",
    )
    parser.add_argument(
        "-r",
        "--header",
        type=str,
        default=".",
        help="Output folder for generated .h file",
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
        args.num_tests = 2 ** (args.width * 2)

    test_a, test_b, all_pps, all_cpls, expected = generate_test_vectors(
        args.width,
        args.encoding,
        args.unsigned,
        args.output,
        args.num_tests,
        exhaustive=args.exhaustive,
    )

    export_defines(args)

    num_pp = len(all_pps[0]) if all_pps else 0
    print(f"\nGenerated {num_pp} partial product files in {args.output}")


if __name__ == "__main__":
    main()
