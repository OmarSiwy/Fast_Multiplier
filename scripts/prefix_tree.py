#!/usr/bin/env python3
"""
Parallel Prefix Tree Generator
Generates hierarchical prefix trees using prefix_cell modules
"""

import argparse
import math
import sys
from typing import List, Tuple, Dict, Set
from dataclasses import dataclass


@dataclass
class Node:
    """Represents a node in the prefix tree"""

    level: int
    index: int
    left_input: Tuple[int, int]  # (level, index) of left input
    right_input: Tuple[int, int]  # (level, index) of right input
    is_input: bool = False
    is_buffer: bool = False  # For forwarding nodes

    def __hash__(self):
        return hash((self.level, self.index))

    def __eq__(self, other):
        return self.level == other.level and self.index == other.index


class PrefixTreeGenerator:
    """Generate parallel prefix trees for carry computation"""

    def __init__(self, width: int, technique: str, pipeline: int = 0):
        self.width = width
        self.technique = technique.lower()
        self.pipeline = pipeline
        self.levels = []
        self.max_level = 0
        self.prefix_tree_stages = 0

        # Validate inputs
        if width < 2 or width > 256:
            raise ValueError(f"Width must be between 2 and 256, got {width}")

        if self.technique not in ["brent-kung", "sklansky", "kogge-stone"]:
            raise ValueError(f"Unknown technique: {technique}")

    def generate_tree(self):
        """Generate the prefix tree structure"""
        if self.technique == "brent-kung":
            self._generate_brent_kung()
        elif self.technique == "sklansky":
            self._generate_sklansky()
        elif self.technique == "kogge-stone":
            self._generate_kogge_stone()

        self.prefix_tree_stages = self.max_level

    def _generate_sklansky(self):
        """
        Generate Sklansky (divide-and-conquer) prefix tree
        - Minimum depth: log2(n)
        - Maximum fanout: n/2
        - Good for low latency, high fanout
        """
        n = self.width
        num_levels = math.ceil(math.log2(n))

        # Initialize with input level
        self.levels = [{}]
        for i in range(n):
            self.levels[0][i] = Node(0, i, (0, i), (0, i), is_input=True)

        # Build tree levels
        for level in range(1, num_levels + 1):
            self.levels.append({})
            step = 1 << level  # 2^level
            half_step = step >> 1

            for i in range(n):
                # Determine if this position needs computation
                # Pattern: within each block of size 'step', positions in the second half
                # combine with the last position of the first half

                # Which block are we in?
                block_num = i // step
                pos_in_block = i % step

                if pos_in_block < half_step:
                    # First half of block: buffer
                    self.levels[level][i] = Node(
                        level, i, (level - 1, i), (level - 1, i), is_buffer=True
                    )
                else:
                    # Second half of block: combine with last element of first half
                    left_idx = i
                    # The "first half" ends at block_start + half_step - 1
                    right_idx = block_num * step + half_step - 1

                    self.levels[level][i] = Node(
                        level,
                        i,
                        (level - 1, left_idx),
                        (level - 1, right_idx),
                        is_buffer=False,
                    )

        self.max_level = num_levels

    def _generate_kogge_stone(self):
        """
        Generate Kogge-Stone prefix tree
        - Minimum depth: log2(n)
        - Maximum fanout: 1
        - Maximum node count (high area)
        - Good for minimum latency
        """
        n = self.width
        num_levels = math.ceil(math.log2(n))

        # Initialize with input level
        self.levels = [{}]
        for i in range(n):
            self.levels[0][i] = Node(0, i, (0, i), (0, i), is_input=True)

        # Build tree levels
        for level in range(1, num_levels + 1):
            self.levels.append({})
            step = 1 << (level - 1)  # 2^(level-1)

            for i in range(n):
                if i < step:
                    # Just propagate from previous level
                    self.levels[level][i] = Node(
                        level, i, (level - 1, i), (level - 1, i), is_buffer=True
                    )
                else:
                    # Compute prefix with step distance
                    self.levels[level][i] = Node(
                        level, i, (level - 1, i), (level - 1, i - step), is_buffer=False
                    )

        self.max_level = num_levels

    def _generate_brent_kung(self):
        """
        Generate Brent-Kung prefix tree
        - Depth: 2*log2(n) - 1
        - Minimum area (fewest nodes)
        - Good for area-constrained designs
        """
        n = self.width
        num_levels_up = math.ceil(math.log2(n))

        # Initialize with input level
        self.levels = [{}]
        for i in range(n):
            self.levels[0][i] = Node(0, i, (0, i), (0, i), is_input=True)

        # Up-sweep phase (reduction)
        for level in range(1, num_levels_up + 1):
            self.levels.append({})
            step = 1 << level  # 2^level

            for i in range(n):
                if (i + 1) % step == 0:
                    # Compute prefix at positions 2^k - 1
                    self.levels[level][i] = Node(
                        level,
                        i,
                        (level - 1, i),
                        (level - 1, i - (step >> 1)),
                        is_buffer=False,
                    )
                else:
                    # Buffer other positions
                    self.levels[level][i] = Node(
                        level, i, (level - 1, i), (level - 1, i), is_buffer=True
                    )

        # Down-sweep phase (distribution)
        for level in range(num_levels_up + 1, 2 * num_levels_up):
            self.levels.append({})
            offset = level - num_levels_up
            step = 1 << (num_levels_up - offset)
            half_step = step >> 1

            for i in range(n):
                # Check if we need to compute at this position
                mod_val = (i + 1) % step
                if mod_val == half_step:
                    # Compute prefix
                    right_idx = ((i + 1) // step) * step - 1
                    if right_idx >= 0 and right_idx < n:
                        self.levels[level][i] = Node(
                            level,
                            i,
                            (level - 1, i),
                            (level - 1, right_idx),
                            is_buffer=False,
                        )
                    else:
                        self.levels[level][i] = Node(
                            level, i, (level - 1, i), (level - 1, i), is_buffer=True
                        )
                else:
                    # Buffer
                    self.levels[level][i] = Node(
                        level, i, (level - 1, i), (level - 1, i), is_buffer=True
                    )

        self.max_level = 2 * num_levels_up - 1

    def generate_verilog(self, output_file: str):
        """Generate SystemVerilog RTL for the prefix tree"""

        with open(output_file, "w") as f:
            self._write_verilog_header(f)
            self._write_verilog_module(f)

    def _write_verilog_header(self, f):
        """Write file header"""
        f.write(
            f"""//
// Parallel Prefix Tree - {self.technique.upper()}
// Width: {self.width} bits
// Levels: {self.max_level}
// Pipeline stages: {self.pipeline}
// Auto-generated by prefix_tree.py
//

"""
        )

    def _write_verilog_module(self, f):
        """Write the main module using prefix_cell instances"""

        # Module declaration
        f.write(f"module prefix_tree #(\n")
        f.write(f"    parameter WIDTH = {self.width},\n")
        f.write(f"    parameter PIPE = {self.pipeline}\n")
        f.write(f") (\n")
        f.write(f"    input  logic clk,\n")
        f.write(f"    input  logic rst,\n")
        f.write(f"    input  logic [WIDTH-1:0] g_in,  // Generate inputs\n")
        f.write(f"    input  logic [WIDTH-1:0] p_in,  // Propagate inputs\n")
        f.write(f"    input  logic [WIDTH-1:0] a_in,  // Auxiliary inputs\n")
        f.write(f"    output logic [WIDTH-1:0] g_out, // Generate outputs (prefix)\n")
        f.write(f"    output logic [WIDTH-1:0] p_out, // Propagate outputs\n")
        f.write(f"    output logic [WIDTH-1:0] a_out  // Auxiliary outputs\n")
        f.write(f");\n\n")

        # Add PREFIX_TREE_STAGES parameter inside module
        f.write(f"    // Prefix tree stages (number of levels)\n")
        f.write(f"    parameter PREFIX_STAGES = {self.max_level};\n\n")

        # Declare internal signals for each level
        for level in range(self.max_level + 1):
            f.write(f"    // Level {level} signals\n")
            f.write(f"    logic [WIDTH-1:0] g_L{level};\n")
            f.write(f"    logic [WIDTH-1:0] p_L{level};\n")
            f.write(f"    logic [WIDTH-1:0] a_L{level};\n")
            f.write(f"\n")

        # Connect inputs to level 0
        f.write(f"    // Connect inputs to level 0\n")
        f.write(f"    assign g_L0 = g_in;\n")
        f.write(f"    assign p_L0 = p_in;\n")
        f.write(f"    assign a_L0 = a_in;\n\n")

        # Generate prefix cells for each level
        for level in range(1, self.max_level + 1):
            f.write(f"    // Level {level} prefix cells\n")
            for i in range(self.width):
                node = self.levels[level][i]
                left_lvl, left_idx = node.left_input
                right_lvl, right_idx = node.right_input

                if node.is_buffer:
                    # Buffer nodes: Use prefix_cell with identity inputs
                    # g_lo=0, p_lo=1, a_lo=0 creates: g_out=g_hi, p_out=p_hi, a_out=a_hi
                    # This ensures proper pipelining when PIPE=1
                    f.write(f"    prefix_cell #(.PIPE(PIPE)) cell_L{level}_{i} (\n")
                    f.write(f"        .clk(clk),\n")
                    f.write(f"        .rst(rst),\n")
                    f.write(f"        .g_hi(g_L{left_lvl}[{left_idx}]),\n")
                    f.write(f"        .p_hi(p_L{left_lvl}[{left_idx}]),\n")
                    f.write(f"        .a_hi(a_L{left_lvl}[{left_idx}]),\n")
                    f.write(f"        .g_lo(1'b0),  // Identity: g_out = g_hi\n")
                    f.write(f"        .p_lo(1'b1),  // Identity: p_out = p_hi\n")
                    f.write(f"        .a_lo(1'b0),  // Identity: a_out = a_hi\n")
                    f.write(f"        .g_out(g_L{level}[{i}]),\n")
                    f.write(f"        .p_out(p_L{level}[{i}]),\n")
                    f.write(f"        .a_out(a_L{level}[{i}])\n")
                    f.write(f"    );\n")
                else:
                    # Instantiate prefix_cell
                    f.write(f"    prefix_cell #(.PIPE(PIPE)) cell_L{level}_{i} (\n")
                    f.write(f"        .clk(clk),\n")
                    f.write(f"        .rst(rst),\n")
                    f.write(f"        .g_hi(g_L{left_lvl}[{left_idx}]),\n")
                    f.write(f"        .p_hi(p_L{left_lvl}[{left_idx}]),\n")
                    f.write(f"        .a_hi(a_L{left_lvl}[{left_idx}]),\n")
                    f.write(f"        .g_lo(g_L{right_lvl}[{right_idx}]),\n")
                    f.write(f"        .p_lo(p_L{right_lvl}[{right_idx}]),\n")
                    f.write(f"        .a_lo(a_L{right_lvl}[{right_idx}]),\n")
                    f.write(f"        .g_out(g_L{level}[{i}]),\n")
                    f.write(f"        .p_out(p_L{level}[{i}]),\n")
                    f.write(f"        .a_out(a_L{level}[{i}])\n")
                    f.write(f"    );\n")
            f.write(f"\n")

        # Connect outputs
        f.write(f"    // Connect outputs from final level\n")
        f.write(f"    assign g_out = g_L{self.max_level};\n")
        f.write(f"    assign p_out = p_L{self.max_level};\n")
        f.write(f"    assign a_out = a_L{self.max_level};\n\n")

        f.write(f"endmodule\n")

    def generate_graphviz(self, output_file: str):
        """Generate GraphViz DOT file for visualization"""

        with open(output_file, "w") as f:
            f.write("digraph PrefixTree {\n")
            f.write("    rankdir=TB;\n")
            f.write("    node [shape=circle];\n\n")

            # Create nodes for each level
            for level in range(self.max_level + 1):
                f.write(f"    // Level {level}\n")
                f.write(f"    {{rank=same;\n")

                for i in range(self.width):
                    node = self.levels[level][i]
                    if node.is_input:
                        f.write(
                            f'        L{level}_{i} [label="{i}", style=filled, fillcolor=lightblue];\n'
                        )
                    elif node.is_buffer:
                        f.write(
                            f'        L{level}_{i} [label="{i}", style=filled, fillcolor=lightgray];\n'
                        )
                    else:
                        f.write(f'        L{level}_{i} [label="{i}"];\n')

                f.write(f"    }}\n\n")

            # Create edges
            for level in range(1, self.max_level + 1):
                for i in range(self.width):
                    node = self.levels[level][i]
                    left_lvl, left_idx = node.left_input
                    right_lvl, right_idx = node.right_input

                    if not node.is_buffer:
                        f.write(
                            f"    L{left_lvl}_{left_idx} -> L{level}_{i} [color=blue];\n"
                        )
                        if left_idx != right_idx or left_lvl != right_lvl:
                            f.write(
                                f"    L{right_lvl}_{right_idx} -> L{level}_{i} [color=red];\n"
                            )
                    else:
                        f.write(
                            f"    L{left_lvl}_{left_idx} -> L{level}_{i} [style=dashed];\n"
                        )

            f.write("}\n")

        print(f"GraphViz file generated: {output_file}")
        print(f"Generate PNG with: dot -Tpng {output_file} -o prefix_tree.png")

    def print_stats(self):
        """Print statistics about the generated tree"""
        print(f"\n{'='*60}")
        print(f"Prefix Tree Statistics - {self.technique.upper()}")
        print(f"{'='*60}")
        print(f"Width: {self.width}")
        print(f"Levels: {self.max_level}")
        print(f"Pipeline stages: {self.pipeline}")

        # Count nodes
        total_nodes = 0
        compute_nodes = 0
        buffer_nodes = 0

        for level in range(1, self.max_level + 1):
            for i in range(self.width):
                node = self.levels[level][i]
                total_nodes += 1
                if node.is_buffer:
                    buffer_nodes += 1
                else:
                    compute_nodes += 1

        print(f"Total nodes: {total_nodes}")
        print(f"Compute nodes: {compute_nodes}")
        print(f"Buffer nodes: {buffer_nodes}")
        print(f"{'='*60}\n")


def main():
    parser = argparse.ArgumentParser(description="Parallel Prefix Tree Generator")
    parser.add_argument(
        "-w", "--width", type=int, required=True, help="Bit width (2-256)"
    )
    parser.add_argument(
        "--technique",
        type=str,
        required=True,
        choices=["brent-kung", "sklansky", "kogge-stone"],
        help="Prefix tree technique",
    )
    parser.add_argument(
        "--pipeline", type=int, default=0, help="Pipeline stages (0=combinational)"
    )
    parser.add_argument(
        "--verilog", action="store_true", help="Generate Verilog output"
    )
    parser.add_argument(
        "--graphviz", action="store_true", help="Generate GraphViz visualization"
    )
    parser.add_argument("--visualize", action="store_true", help="Alias for --graphviz")
    parser.add_argument(
        "-o",
        "--output",
        type=str,
        default="rtl/prefix_tree.sv",
        help="Output Verilog file",
    )
    parser.add_argument("--stats", action="store_true", help="Print statistics")

    args = parser.parse_args()

    # Create generator
    gen = PrefixTreeGenerator(args.width, args.technique, args.pipeline)

    # Generate tree
    gen.generate_tree()

    # Generate outputs
    if args.verilog:
        gen.generate_verilog(args.output)
        print(f"Verilog generated: {args.output}")

    if args.graphviz or args.visualize:
        dot_file = args.output.replace(".sv", ".dot")
        gen.generate_graphviz(dot_file)

    if args.stats or (not args.verilog and not args.graphviz and not args.visualize):
        gen.print_stats()


if __name__ == "__main__":
    main()
