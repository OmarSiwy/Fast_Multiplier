#!/usr/bin/env python3
"""
Compressor Tree Generator using Bit Heap Construction
Generates optimized SystemVerilog code for compressor trees
Supports: Dadda, Bickerstaff, FA-only algorithms
Supports: Signed/Unsigned Binary and Booth (Radix-4) encoding
Uses Baugh-Wooley sign extension optimization
"""

from gen_verilog import generate_verilog
from gen_graphviz import generate_graphviz
from visualize_heap import visualize_before_after_rich
import sys
import os


def dadda_sequence(n):
    """Generate Dadda height sequence up to/past n
    Sequence: 2, 3, 4, 6, 9, 13, 19, 28, ...
    Formula: d[j+1] = floor(3/2 * d[j])
    """
    seq = [2]
    while seq[-1] < n:
        seq.append(int(seq[-1] * 3 // 2))
    return seq


def compute_stages(n):
    """Compute number of stages needed for n partial products"""
    seq = dadda_sequence(n)
    return len(seq) - 1


class BitHeap:
    """Represents a bit heap - collection of bits at each position"""

    def __init__(self, width):
        self.width = width
        # Each heap entry is (bit_name, bit_type)
        # bit_type: 'normal', 'inverted_msb', 'sign_ext', 'fa_sum', 'fa_carry', 'ha_sum', 'ha_carry'
        self.heap = [[] for _ in range(width)]

    def add_bit(self, position, bit_name, bit_type="normal"):
        """Add a bit to the heap at given position with type"""
        if 0 <= position < self.width:
            self.heap[position].append((bit_name, bit_type))

    def add_word(self, word_name, word_width, offset=0, is_signed=False):
        """Add a word (partial product) to the heap"""
        for i in range(word_width):
            pos = offset + i
            if is_signed and i == word_width - 1:
                # Mark MSB as inverted if using optimized sign extension
                self.add_bit(pos, f"{word_name}[{i}]", "inverted_msb")
            else:
                self.add_bit(pos, f"{word_name}[{i}]", "normal")

    def height(self, position):
        """Get height of heap at given position"""
        return len(self.heap[position])

    def max_height(self):
        """Get maximum heap height"""
        return max(len(col) for col in self.heap) if self.heap else 0

    def pop_bits(self, position, count):
        """Remove and return count bits from the BOTTOM (start) of position"""
        bits = self.heap[position][:count]
        self.heap[position] = self.heap[position][count:]
        return bits

    def pop_bits_from_top(self, position, count):
        """Remove and return count bits from the TOP (end) of position"""
        if position < len(self.heap):
            bits = (
                self.heap[position][-count:]
                if count <= len(self.heap[position])
                else self.heap[position]
            )
            self.heap[position] = (
                self.heap[position][:-count]
                if count <= len(self.heap[position])
                else []
            )
            return bits
        return []

    def __str_before_after__(
        self, before_heap, after_heap, stage_num, target_height, algorithm="dadda"
    ):
        fa_input_map, ha_input_map = self._build_input_maps_from_data(after_heap)
        circuit_summary = self._build_circuit_summary(
            before_heap, after_heap, stage_num
        )
        return visualize_before_after_rich(
            before_heap,
            after_heap,
            stage_num,
            target_height,
            fa_input_map,
            ha_input_map,
            circuit_summary,
            width=self.width,
        )

    def _build_input_maps_from_data(self, after_heap):
        """Build maps showing which input bits went into FAs (3) and HAs (2) using actual consumption data"""
        fa_inputs = set()
        ha_inputs = set()

        # Use the stored consumption information
        if hasattr(after_heap, "fa_consumed") and hasattr(after_heap, "ha_consumed"):
            for col in range(self.width):
                # Mark FA inputs
                for start_idx in after_heap.fa_consumed[col]:
                    fa_inputs.add((col, start_idx))
                    fa_inputs.add((col, start_idx + 1))
                    fa_inputs.add((col, start_idx + 2))

                # Mark HA inputs
                for start_idx in after_heap.ha_consumed[col]:
                    ha_inputs.add((col, start_idx))
                    ha_inputs.add((col, start_idx + 1))
        else:
            print(f"WARNING: after_heap missing consumption data!")

        return fa_inputs, ha_inputs

    def _build_circuit_summary(self, before_heap, after_heap, stage_num):
        """Build a summary of FA/HA cells showing counts per column"""
        summary_lines = []

        # Count FAs and HAs by analyzing the after_heap
        fa_locations = {}
        ha_locations = {}

        for col_idx in range(self.width):
            for h_idx, (bit_name, bit_type) in enumerate(after_heap.heap[col_idx]):
                if bit_type == "fa_sum":
                    if col_idx not in fa_locations:
                        fa_locations[col_idx] = []
                    fa_locations[col_idx].append(h_idx)
                elif bit_type == "ha_sum":
                    if col_idx not in ha_locations:
                        ha_locations[col_idx] = []
                    ha_locations[col_idx].append(h_idx)

        # Build summary for each column
        total_fa = sum(len(fas) for fas in fa_locations.values())
        total_ha = sum(len(has) for has in ha_locations.values())

        summary_lines.append(f"Total: {total_fa} Full Adders, {total_ha} Half Adders")
        summary_lines.append("")

        # Show column-by-column breakdown
        for col in sorted(set(list(fa_locations.keys()) + list(ha_locations.keys()))):
            fa_count = len(fa_locations.get(col, []))
            ha_count = len(ha_locations.get(col, []))

            parts = []
            if fa_count > 0:
                parts.append(f"{fa_count} FA")
            if ha_count > 0:
                parts.append(f"{ha_count} HA")

            if parts:
                summary_lines.append(f"  Column {col:2d}: {', '.join(parts)}")

        return summary_lines


class CompressorTreeGenerator:
    def __init__(
        self,
        w=16,
        num_pp=None,
        sign_ext_opt=True,
        unsigned=False,
        encoding="booth",
        algorithm="dadda",
    ):
        self.w = w
        self.encoding = encoding
        self.algorithm = algorithm
        self.unsigned = unsigned
        self.sign_ext_opt = sign_ext_opt

        # For Pipelining
        self.compressor_tree_stages = 0

        # Calculate num_pp based on encoding
        if num_pp is None:
            if encoding == "booth":
                self.num_pp = (w + 1) // 2
            else:  # binary
                self.num_pp = w
        else:
            self.num_pp = num_pp

        self.prod_width = 2 * w
        self.num_stages = 0
        self.stages = []

        # Track all FA/HA instances for SystemVerilog generation
        self.fa_instances = []  # (stage, col, index, inputs)
        self.ha_instances = []  # (stage, col, index, inputs)

        self.build_reduction()

    def build_reduction(self):
        """Build bit heap reduction stages"""
        initial_heap = BitHeap(self.prod_width)

        print(f"\nDEBUG: Building bit heap")
        print(
            f"  algorithm={self.algorithm}, encoding={self.encoding}, unsigned={self.unsigned}"
        )
        print(f"  w={self.w}, num_pp={self.num_pp}, prod_width={self.prod_width}")

        # =================================================================
        # Binary & Booth Logic Start
        # =================================================================

        if self.encoding == "binary":
            if self.unsigned:
                # Unsigned binary multiplication
                # Each PP is unshifted, shifts handled in compression
                for pp_idx in range(self.num_pp):
                    offset = pp_idx
                    for bit in range(self.w):
                        bit_pos = offset + bit
                        if bit_pos < self.prod_width:
                            initial_heap.add_bit(
                                bit_pos, f"pp[{pp_idx}][{bit}]", "normal"
                            )
            else:
                # Signed binary multiplication using Baugh-Wooley
                # Process rows 0 through w-2
                for row in range(self.w - 1):
                    offset = row
                    
                    # Regular bits (LSB through w-2)
                    for bit in range(self.w - 1):
                        pos = offset + bit
                        if pos < self.prod_width:
                            initial_heap.add_bit(pos, f"pp[{row}][{bit}]", "normal")
                    
                    # MSB is inverted
                    msb_pos = offset + self.w - 1
                    if msb_pos < self.prod_width:
                        initial_heap.add_bit(msb_pos, f"pp[{row}][{self.w-1}]", "inverted_msb")
                # Last row (row w-1): b[w-1] is the sign bit
                last_row = self.w - 1
                offset = last_row
                
                # All bits except MSB are inverted
                for bit in range(self.w - 1):
                    pos = offset + bit
                    if pos < self.prod_width:
                        initial_heap.add_bit(pos, f"pp[{last_row}][{bit}]", "inverted_msb")
                msb_pos = offset + self.w - 1
                if msb_pos < self.prod_width:
                    initial_heap.add_bit(msb_pos, f"pp[{last_row}][{self.w-1}]", "normal")
                
                # Baugh-Wooley correction bits
                initial_heap.add_bit(self.w, "1'b1", "normal")  # Correction at position w
                if 2 * self.w - 1 < self.prod_width:
                    initial_heap.add_bit(2 * self.w - 1, "1'b1", "normal")  # Correction at MSB

        elif self.encoding == "booth":
            # Signed Booth Radix-4 encoding
            if self.unsigned:
                raise ValueError("Unsigned Booth multiplication not supported")
            for pp_idx in range(self.num_pp):
                offset = pp_idx * 2

                # Add regular bits (0 to w-1)
                for bit in range(self.w):
                    bit_pos = offset + bit
                    if bit_pos < self.prod_width:
                        initial_heap.add_bit(bit_pos, f"pp[{pp_idx}][{bit}]", "normal")

                # Add inverted MSB at position offset + w
                msb_pos = offset + self.w
                if msb_pos < self.prod_width:
                    initial_heap.add_bit(
                        msb_pos, f"pp[{pp_idx}][{self.w}]", "inverted_msb"
                    )
                # Add correction bit (cpl)
                if msb_pos < self.prod_width:
                    initial_heap.add_bit(msb_pos, f"cpl[{pp_idx}]", "normal")
                # Add sign extension bits
                for ext_pos in range(msb_pos + 1, self.prod_width):
                    initial_heap.add_bit(ext_pos, f"pp[{pp_idx}][{self.w}]", "normal")

        # =================================================================
        # Binary & Booth Logic End
        # =================================================================

        print(f"\nDEBUG: Heap heights after PP generation:")
        print(f"  {[len(col) for col in initial_heap.heap[:self.prod_width]]}")

        # Initialize empty consumption data
        initial_heap.fa_consumed = [[] for _ in range(self.prod_width)]
        initial_heap.ha_consumed = [[] for _ in range(self.prod_width)]

        self.stages.append(self.copy_heap(initial_heap))
        print(f"DEBUG: After copy_heap, stages[{len(self.stages)-1}].heap[0] has {len(self.stages[-1].heap[0])} bits")

        # Build reduction stages based on algorithm
        if self.algorithm == 'dadda':
            initial_max = initial_heap.max_height()
            self.dadda_seq = dadda_sequence(initial_max)

            targets = [h for h in reversed(self.dadda_seq) if h < initial_max]
            print(f"  Dadda sequence: {self.dadda_seq}")
            print(f"  Initial max height: {initial_max}")
            print(f"  Reduction targets: {targets}")

            current_heap = initial_heap
            for target in targets:
                print(f"  Stage {self.num_stages + 1}: reducing from {current_heap.max_height()} to {target}")
                next_heap = self.reduce_stage_dadda(current_heap, target)
                print(f"    Result: max_height = {next_heap.max_height()}")
                self.stages.append(self.copy_heap(next_heap))
                print(f"DEBUG: After copy_heap, stages[{len(self.stages)-1}].heap[0] has {len(self.stages[-1].heap[0])} bits")
                current_heap = next_heap
                self.num_stages += 1
        elif self.algorithm == 'faonly':
            # FA-only greedy: keep using FAs until no column has 3+ bits
            self.dadda_seq = []

            initial_max = initial_heap.max_height()
            print(f"  FA-only greedy reduction")
            print(f"  Initial max height: {initial_max}")

            current_heap = initial_heap
            stage_limit = 50
            stage_count = 0

            # Continue until no column has 3+ bits
            while True:
                # Check if any column has 3+ bits
                any_reducible = any(current_heap.height(col) >= 3 for col in range(self.prod_width - 1))
                if not any_reducible:
                    print(f"  FA-only complete: no columns with 3+ bits")
                    break

                print(f"  FA-only stage {stage_count + 1}: max_height = {current_heap.max_height()}")
                next_heap = self.reduce_stage_faonly(current_heap)
                print(f"    After reduction: max_height = {next_heap.max_height()}")

                self.stages.append(self.copy_heap(next_heap))
                current_heap = next_heap
                self.num_stages += 1
                stage_count += 1

                if stage_count >= stage_limit:
                    print("WARNING: Reached stage limit")
                    break
        else:  # bickerstaff
            self.dadda_seq = []

            initial_max = initial_heap.max_height()
            dadda_seq_temp = dadda_sequence(initial_max)
            targets = [h for h in reversed(dadda_seq_temp) if h < initial_max]
            print(f"  Bickerstaff using Dadda targets: {targets}")
            print(f"  Initial max height: {initial_max}")

            current_heap = initial_heap
            stage_limit = 50
            stage_count = 0
            for target in targets:
                print(f"  Bickerstaff stage {stage_count + 1}: max_height = {current_heap.max_height()}, target = {target}")
                next_heap = self.reduce_stage_bickerstaff(current_heap, target)
                print(f"    After reduction: max_height = {next_heap.max_height()}")

                self.stages.append(self.copy_heap(next_heap))
                current_heap = next_heap
                self.num_stages += 1
                stage_count += 1

                if stage_count >= stage_limit:
                    print("WARNING: Reached stage limit")
                    break

    def copy_heap(self, heap):
        """Create a deep copy of a heap"""
        new_heap = BitHeap(heap.width)
        for col_idx, col in enumerate(heap.heap):
            new_heap.heap[col_idx] = col.copy()

        if hasattr(heap, "fa_consumed"):
            new_heap.fa_consumed = [lst.copy() for lst in heap.fa_consumed]
        if hasattr(heap, "ha_consumed"):
            new_heap.ha_consumed = [lst.copy() for lst in heap.ha_consumed]

        return new_heap

    def reduce_stage_faonly(self, heap):
        """Reduce heap using only FAs"""
        next_heap = BitHeap(self.prod_width)
        fa_count = 0

        fa_consumed = [[] for _ in range(self.prod_width)]
        ha_consumed = [[] for _ in range(self.prod_width)]

        for col in range(self.prod_width):
            working_bits = heap.heap[col].copy()
            bit_index = 0

            # Use FAs while we have 3+ bits available and not in the last column
            if col < self.prod_width - 1:
                while len(working_bits) >= 3:
                    # Take 3 bits and create FA
                    bits = [working_bits.pop(0) for _ in range(3)]
                    fa_consumed[col].append(bit_index)

                    fa_name = f"fa_s{self.num_stages}_c{col}_n{fa_count}"
                    inputs = [bit[0] for bit in bits]
                    self.fa_instances.append((self.num_stages, col, fa_count, inputs))

                    next_heap.add_bit(col, f"{fa_name}_s", "fa_sum")
                    next_heap.add_bit(col + 1, f"{fa_name}_c", "fa_carry")
                    fa_count += 1
                    bit_index += 3

            # Pass through remaining bits
            for bit_name, bit_type in working_bits:
                next_heap.add_bit(col, bit_name, bit_type)

        next_heap.fa_consumed = fa_consumed
        next_heap.ha_consumed = ha_consumed
        return next_heap

    def reduce_stage_dadda(self, heap, target_height):
        """Reduce heap to target height using FAs and HAs (Dadda algorithm)"""
        next_heap = BitHeap(self.prod_width)
        fa_count = 0
        ha_count = 0

        fa_consumed = [[] for _ in range(self.prod_width)]
        ha_consumed = [[] for _ in range(self.prod_width)]

        for col in range(self.prod_width):
            working_bits = heap.heap[col].copy()
            bit_index = 0

            def current_height():
                return len(working_bits) + next_heap.height(col)

            if col < self.prod_width - 1:
                # Use FAs while we have 3+ bits AND height > target
                while len(working_bits) >= 3 and current_height() > target_height:
                    # Check if we only need to reduce by 1 (use HA instead)
                    if current_height() == target_height + 1 and len(working_bits) >= 2:
                        break

                    # Need to reduce by 2+, use FA
                    bits = [working_bits.pop(0) for _ in range(3)]
                    fa_consumed[col].append(bit_index)

                    fa_name = f"fa_s{self.num_stages}_c{col}_n{fa_count}"
                    inputs = [bit[0] for bit in bits]
                    self.fa_instances.append((self.num_stages, col, fa_count, inputs))

                    next_heap.add_bit(col, f"{fa_name}_s", "fa_sum")
                    next_heap.add_bit(col + 1, f"{fa_name}_c", "fa_carry")
                    fa_count += 1
                    bit_index += 3

                # Use HA if we're exactly 1 over target and have 2+ bits
                if len(working_bits) >= 2 and current_height() == target_height + 1:
                    bits = [working_bits.pop(0) for _ in range(2)]
                    ha_consumed[col].append(bit_index)

                    ha_name = f"ha_s{self.num_stages}_c{col}_n{ha_count}"
                    inputs = [bit[0] for bit in bits]
                    self.ha_instances.append((self.num_stages, col, ha_count, inputs))

                    next_heap.add_bit(col, f"{ha_name}_s", "ha_sum")
                    next_heap.add_bit(col + 1, f"{ha_name}_c", "ha_carry")
                    ha_count += 1
                    bit_index += 2

            # Pass through remaining bits
            for bit_name, bit_type in working_bits:
                next_heap.add_bit(col, bit_name, bit_type)


            # DEBUG
            if col == 0:
                print(f"DEBUG Stage {self.num_stages}: Column 0 after passthrough has {len(next_heap.heap[0])} bits")
                for bit in next_heap.heap[0]:
                    print(f"  - {bit}")

        next_heap.fa_consumed = fa_consumed
        next_heap.ha_consumed = ha_consumed
        return next_heap

    def reduce_stage_bickerstaff(self, heap, target_height):
        """Reduce heap using ASAP approach (Bickerstaff algorithm)"""
        next_heap = BitHeap(self.prod_width)
        fa_count = 0
        ha_count = 0

        fa_consumed = [[] for _ in range(self.prod_width)]
        ha_consumed = [[] for _ in range(self.prod_width)]

        rightmost_2bit_col = -1
        for col in range(self.prod_width):
            num_bits = heap.height(col)
            remaining = num_bits % 3
            if remaining == 2:
                rightmost_2bit_col = col
                break

        for col in range(self.prod_width):
            num_bits = heap.height(col)

            if num_bits > 0:
                print(f"    Col {col}: {num_bits} bits", end="")

            fa_this_col = 0
            bits_consumed = 0
            while bits_consumed + 3 <= num_bits and col < self.prod_width - 1:
                bits = heap.pop_bits(col, 3)
                fa_consumed[col].append(bits_consumed)

                # Store FA instance data
                fa_name = f"fa_s{self.num_stages}_c{col}_n{fa_count}"
                inputs = [bit[0] for bit in bits]
                self.fa_instances.append((self.num_stages, col, fa_count, inputs))

                next_heap.add_bit(col, f"{fa_name}_s", 'fa_sum')
                next_heap.add_bit(col + 1, f"{fa_name}_c", 'fa_carry')
                fa_count += 1
                fa_this_col += 1
                bits_consumed += 3

            remaining = num_bits - bits_consumed
            current_height = remaining + next_heap.height(col)

            ha_this_col = 0
            if remaining == 2 and col < self.prod_width - 1:
                use_ha = (current_height > target_height) or (col == rightmost_2bit_col)
                if use_ha:
                    bits = heap.pop_bits(col, 2)
                    ha_consumed[col].append(bits_consumed)

                    # Store HA instance data
                    ha_name = f"ha_s{self.num_stages}_c{col}_n{ha_count}"
                    inputs = [bit[0] for bit in bits]
                    self.ha_instances.append((self.num_stages, col, ha_count, inputs))

                    next_heap.add_bit(col, f"{ha_name}_s", 'ha_sum')
                    next_heap.add_bit(col + 1, f"{ha_name}_c", 'ha_carry')
                    ha_count += 1
                    ha_this_col += 1
                    bits_consumed += 2

            for bit_name, bit_type in heap.heap[col]:
                next_heap.add_bit(col, bit_name, bit_type)

            if num_bits > 0:
                print(f" → {fa_this_col}FA + {ha_this_col}HA")

        print(f"    Total: {fa_count} FAs, {ha_count} HAs")

        next_heap.fa_consumed = fa_consumed
        next_heap.ha_consumed = ha_consumed
        return next_heap

    def print_summary(self):
        """Print generation summary with heap visualization"""
        algo_name = {
            "dadda": "Dadda",
            "bickerstaff": "Bickerstaff",
            "faonly": "FA-only Greedy",
        }[self.algorithm]
        print(f"\n{algo_name} Tree Configuration:")
        print(f"  Algorithm: {self.algorithm.upper()}")
        print(f"  Input Width: {self.w} bits")
        print(
            f"  Encoding: {self.encoding.upper()} ({'Radix-4 Booth' if self.encoding == 'booth' else 'Radix-2 Binary'})"
        )
        print(f"  Partial Products: {self.num_pp}")
        print(f"  Product Width: {self.prod_width}")
        print(f"  Multiplication Type: {'Unsigned' if self.unsigned else 'Signed'}")
        if not self.unsigned:
            print(
                f"  Sign Extension: {'Optimized (invert+extend)' if self.sign_ext_opt else 'Naive'}"
            )
        if self.algorithm == "dadda":
            print(f"  Dadda Sequence: {self.dadda_seq}")
        print(f"  Number of Stages: {self.num_stages}")
        print()

        print(f"Initial Partial Products (Stage 0):")
        print(self.stages[0])
        print()

        if self.algorithm == "dadda":
            initial_max = self.stages[0].max_height()
            targets = [h for h in reversed(self.dadda_seq) if h < initial_max]
        else:
            targets = []

        for idx in range(1, len(self.stages)):
            if idx - 1 < len(targets):
                target = targets[idx - 1]
            else:
                target = self.stages[idx - 1].max_height()
            print(
                self.stages[0].__str_before_after__(
                    self.stages[idx - 1], self.stages[idx], idx, target, self.algorithm
                )
            )
            print()

        print("\n" + "=" * 80)
        generate_graphviz(self, "graph.dot", show_final_adder=True)

        print("Graphviz DOT file saved to: graph.dot")
        print("Generate visualization with:")
        print("  dot -Tpdf graph.dot -o graph.pdf")
        print()


def main():
    import argparse

    parser = argparse.ArgumentParser(
        description="Generate Dadda/Bickerstaff/FAonly Compressor Tree"
    )
    parser.add_argument("-w", "--width", type=int, default=16, help="Input width")
    parser.add_argument(
        "-n", "--num-pp", type=int, default=None, help="Number of partial products"
    )
    parser.add_argument(
        "-e",
        "--encoding",
        type=str,
        default="booth",
        choices=["booth", "binary"],
        help="Encoding type",
    )
    parser.add_argument(
        "-a",
        "--algorithm",
        type=str,
        default="dadda",
        choices=["dadda", "bickerstaff", "faonly"],
        help="Reduction algorithm",
    )
    parser.add_argument(
        "-o", "--output", type=str, default="compressor_tree.sv", help="Output file"
    )
    parser.add_argument(
        "-r", "--header", type=str, default=".", help="Output folder for header file"
    )
    parser.add_argument("-s", "--summary", action="store_true", help="Print summary")
    parser.add_argument(
        "-v", "--visualize", action="store_true", help="Generate visualization"
    )
    parser.add_argument(
        "--naive-sign-ext", action="store_true", help="Use naive sign extension"
    )
    parser.add_argument(
        "--unsigned", action="store_true", help="Unsigned multiplication"
    )

    args = parser.parse_args()

    # Validate: Booth encoding only supports signed
    if args.encoding == "booth" and args.unsigned:
        print("ERROR: Unsigned Booth multiplication not supported", file=sys.stderr)
        sys.exit(1)

    gen = CompressorTreeGenerator(
        w=args.width,
        num_pp=args.num_pp,
        sign_ext_opt=not args.naive_sign_ext,
        unsigned=args.unsigned,
        encoding=args.encoding,
        algorithm=args.algorithm,
    )

    if args.summary or args.visualize:
        mult_type = "Unsigned" if args.unsigned else "Signed"
        encoding_name = (
            "Radix-4 Booth" if args.encoding == "booth" else "Radix-2 Binary"
        )
        algorithm_names = {
            "dadda": "Dadda (ALAP)",
            "bickerstaff": "Bickerstaff (ASAP)",
            "faonly": "FA-only (Greedy)",
        }
        algorithm_name = algorithm_names[args.algorithm]

        print(f"\n{algorithm_name} Tree Configuration:")
        print(f"  Input Width: {args.width} bits")
        print(f"  Encoding: {encoding_name}")
        print(f"  Type: {mult_type}")
        print(f"  Partial Products: {gen.num_pp}")
        print(f"  Product Width: {gen.prod_width}")
        print(f"  Stages: {gen.num_stages}")
        print(f"  Final heap height: {gen.stages[-1].max_height()}")

        if args.visualize:
            gen.print_summary()

    generate_verilog(gen, args.output)

    print(f"\nGenerated {args.output}")


if __name__ == "__main__":
    main()
