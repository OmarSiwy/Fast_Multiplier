#!/usr/bin/env python3
"""
SystemVerilog Generator for Dadda/Bickerstaff Compressor Trees
"""


class VerilogGenerator:
    def __init__(self, dadda_gen):
        """
        Initialize with a DaddaGenerator instance

        Args:
            dadda_gen: DaddaGenerator object containing stages, FA/HA instances, etc.
        """
        self.gen = dadda_gen
        self.w = dadda_gen.w
        self.prod_width = dadda_gen.prod_width
        self.num_pp = dadda_gen.num_pp
        self.unsigned = dadda_gen.unsigned
        self.encoding = dadda_gen.encoding
        if (self.unsigned) and (self.encoding == "booth"):
            self.num_pp = dadda_gen.num_pp + 1
        self.num_stages = dadda_gen.num_stages
        self.stages = dadda_gen.stages
        self.fa_instances = dadda_gen.fa_instances
        self.ha_instances = dadda_gen.ha_instances
        self.sign_ext_opt = dadda_gen.sign_ext_opt
        self.algorithm = dadda_gen.algorithm

    def generate_module(self):
        """Generate complete SystemVerilog module with FA/HA instantiations"""
        lines = []

        lines.extend(self._generate_header())
        lines.extend(self._generate_module_declaration())
        lines.extend(self._generate_wire_declarations())
        lines.extend(self._generate_stage_signals())
        lines.extend(self._generate_stage0_assignment())
        lines.extend(self._generate_reduction_stages())
        lines.extend(self._generate_final_outputs())

        lines.append("endmodule")

        return "\n".join(lines)

    def _generate_header(self):
        """Generate module header comment"""
        lines = [
            "//",
            f"// {'Dadda' if self.algorithm == 'dadda' else 'Bickerstaff'} Tree Compressor",
            f"// Algorithm: {self.algorithm.upper()}",
            f"// Input Width: {self.w} bits",
            f"// Encoding: {self.encoding.upper()}",
            f"// Type: {'Unsigned' if self.unsigned else 'Signed'}",
            f"// Partial Products: {self.num_pp}",
            f"// Product Width: {self.prod_width}",
            f"// Reduction Stages: {self.num_stages}",
            "//",
            "",
        ]
        return lines

    def _generate_module_declaration(self):
        """Generate module declaration with ports - USES PACKED 2D ARRAYS"""
        lines = [
            f"module compressor_tree #(",
            f"    parameter PIPE = 0",
            f")(",
            f"    input logic clk,",
            f"    input logic rst,",
        ]

        if self.encoding == "booth":
            lines.append(f"    input logic [{self.num_pp-1}:0][{self.w}:0] pp,")
        else:
            lines.append(f"    input logic [{self.num_pp-1}:0][{self.w-1}:0] pp,")

        if self.encoding == "booth":
            lines.append(f"    /* verilator lint_off ASCRANGE */")
            if self.unsigned:
                lines.append(f"    input logic [0:{self.num_pp-2}] cpl,")
            else:
                lines.append(f"    input logic [0:{self.num_pp-1}] cpl,")
            lines.append(f"    /* verilator lint_on ASCRANGE */")

        lines.extend(
            [
                f"    output logic [{self.prod_width-1}:0] sum,",
                f"    output logic [{self.prod_width-1}:0] carry",
                ");",
                "",
            ]
        )

        # Damir Change to support pipeling
        lines.extend(
            [
                f"    parameter COMPRESSOR_TREE_STAGES = {self.gen.compressor_tree_stages};",
                "",
            ]
        )

        return lines

    def _generate_wire_declarations(self):
        """Generate FA and HA output wire declarations"""
        lines = ["    // FA and HA output wires"]

        for stage_idx, col, idx, inputs in self.fa_instances:
            fa_name = f"fa_s{stage_idx}_c{col}_n{idx}"
            lines.append(f"    logic {fa_name}_s, {fa_name}_c;")

        for stage_idx, col, idx, inputs in self.ha_instances:
            ha_name = f"ha_s{stage_idx}_c{col}_n{idx}"
            lines.append(f"    logic {ha_name}_s, {ha_name}_c;")

        lines.append("")
        return lines

    def _generate_stage_signals(self):
        """Generate internal stage signal declarations"""
        lines = []

        for stage_idx in range(self.num_stages + 1):
            lines.append(f"    // Stage {stage_idx} signals")
            stage_heap = self.stages[stage_idx]

            # DEBUG
            if stage_idx == 2:
                print(
                    f"DEBUG _generate_stage_signals stage 2: col0 has {len(stage_heap.heap[0])} bits"
                )

            for col in range(self.prod_width):
                col_bits = stage_heap.heap[col]
                if len(col_bits) > 0:
                    lines.append(
                        f"    logic [{len(col_bits)-1}:0] stage{stage_idx}_col{col};"
                    )
            lines.append("")

        return lines

    def _generate_stage0_assignment(self):
        """Generate Stage 0 partial product assignments"""
        lines = ["    // Stage 0: Partial Product Assignment"]
        stage0_heap = self.stages[0]

        for col in range(self.prod_width):
            for bit_idx, (bit_name, bit_type) in enumerate(stage0_heap.heap[col]):
                if bit_type == "inverted_msb":
                    lines.append(
                        f"    assign stage0_col{col}[{bit_idx}] = ~{bit_name};"
                    )
                elif bit_type == "correction" or "1'b1" in bit_name:
                    lines.append(f"    assign stage0_col{col}[{bit_idx}] = 1'b1;")
                else:
                    lines.append(f"    assign stage0_col{col}[{bit_idx}] = {bit_name};")

        lines.append("")
        return lines

    def _generate_reduction_stages(self):
        """Generate all reduction stages with FA/HA instantiations"""
        lines = []

        for stage_idx in range(self.num_stages):
            lines.extend(self._generate_single_reduction_stage(stage_idx))

        return lines

    def _generate_single_reduction_stage(self, stage_idx):
        """Generate a single reduction stage"""
        lines = [f"    // Stage {stage_idx + 1}: Reduction"]

        # Get FAs and HAs for this stage
        stage_fas = [
            (col, idx, inputs)
            for s, col, idx, inputs in self.fa_instances
            if s == stage_idx
        ]
        stage_has = [
            (col, idx, inputs)
            for s, col, idx, inputs in self.ha_instances
            if s == stage_idx
        ]

        # Group by column
        fas_by_col = {}
        has_by_col = {}

        for col, idx, inputs in stage_fas:
            if col not in fas_by_col:
                fas_by_col[col] = []
            fas_by_col[col].append((idx, inputs))

        for col, idx, inputs in stage_has:
            if col not in has_by_col:
                has_by_col[col] = []
            has_by_col[col].append((idx, inputs))

        # Track bit consumption
        col_bit_idx = {}

        # Instantiate FAs
        for col in sorted(fas_by_col.keys()):
            if col not in col_bit_idx:
                col_bit_idx[col] = 0

            for idx, inputs in fas_by_col[col]:
                fa_name = f"fa_s{stage_idx}_c{col}_n{idx}"
                lines.extend(
                    [
                        f"    fa {fa_name} (",
                        f"        .a(stage{stage_idx}_col{col}[{col_bit_idx[col]}]),",
                        f"        .b(stage{stage_idx}_col{col}[{col_bit_idx[col] + 1}]),",
                        f"        .c_in(stage{stage_idx}_col{col}[{col_bit_idx[col] + 2}]),",
                        f"        .s({fa_name}_s),",
                        f"        .c_out({fa_name}_c)",
                        f"    );",
                        "",
                    ]
                )
                col_bit_idx[col] += 3

        # Instantiate HAs
        for col in sorted(has_by_col.keys()):
            if col not in col_bit_idx:
                col_bit_idx[col] = 0

            for idx, inputs in has_by_col[col]:
                ha_name = f"ha_s{stage_idx}_c{col}_n{idx}"
                lines.extend(
                    [
                        f"    ha {ha_name} (",
                        f"        .a(stage{stage_idx}_col{col}[{col_bit_idx[col]}]),",
                        f"        .b(stage{stage_idx}_col{col}[{col_bit_idx[col] + 1}]),",
                        f"        .s({ha_name}_s),",
                        f"        .c_out({ha_name}_c)",
                        f"    );",
                        "",
                    ]
                )
                col_bit_idx[col] += 2

        # Map to next stage
        lines.extend(self._generate_stage_mapping(stage_idx, col_bit_idx))

        return lines

    def _generate_stage_mapping(self, stage_idx, col_bit_idx):
        """Generate mapping from current stage to next stage"""
        lines = [f"    // Map to Stage {stage_idx + 1} columns"]

        next_heap = self.stages[stage_idx + 1]
        prev_heap = self.stages[stage_idx]

        for col in range(self.prod_width):
            next_col_bits = next_heap.heap[col]

            for bit_idx, (bit_name, bit_type) in enumerate(next_col_bits):
                if bit_type in ["fa_sum", "fa_carry", "ha_sum", "ha_carry"]:
                    # This is an FA/HA output - check if it's from the current stage
                    if f"_s{stage_idx}_" in bit_name:
                        # New output from THIS stage - use wire directly
                        lines.append(
                            f"    assign stage{stage_idx + 1}_col{col}[{bit_idx}] = {bit_name};"
                        )
                    else:
                        # FA/HA output from a previous stage that passed through
                        # It must exist in the previous stage's column
                        found = False
                        for prev_bit_idx, (prev_bit_name, prev_bit_type) in enumerate(
                            prev_heap.heap[col]
                        ):
                            if prev_bit_name == bit_name:
                                lines.append(
                                    f"    assign stage{stage_idx + 1}_col{col}[{bit_idx}] = stage{stage_idx}_col{col}[{prev_bit_idx}];"
                                )
                                found = True
                                break

                        if not found:
                            # Shouldn't happen - fallback
                            lines.append(
                                f"    assign stage{stage_idx + 1}_col{col}[{bit_idx}] = {bit_name};"
                            )
                else:
                    # Passthrough bit - it MUST exist in the previous stage
                    found = False
                    for prev_bit_idx, (prev_bit_name, prev_bit_type) in enumerate(
                        prev_heap.heap[col]
                    ):
                        if prev_bit_name == bit_name:
                            lines.append(
                                f"    assign stage{stage_idx + 1}_col{col}[{bit_idx}] = stage{stage_idx}_col{col}[{prev_bit_idx}];"
                            )
                            found = True
                            break

                    if not found:
                        # This shouldn't happen with proper heap tracking
                        print(
                            f"WARNING: Bit {bit_name} not found in stage {stage_idx} column {col}"
                        )
                        lines.append(
                            f"    assign stage{stage_idx + 1}_col{col}[{bit_idx}] = {bit_name};"
                        )

        lines.append("")
        return lines

    def _generate_final_outputs(self):
        """Generate final sum and carry output assignments"""
        lines = ["    // Final outputs (sum and carry)"]

        final_stage = self.num_stages
        final_heap = self.stages[final_stage]

        # DEBUG
        print(f"DEBUG _generate_final_outputs: final_stage={final_stage}")
        print(f"DEBUG: Column 0 has {len(final_heap.heap[0])} bits")
        for bit in final_heap.heap[0]:
            print(f"  - {bit}")

        for col in range(self.prod_width):
            bits = final_heap.heap[col]

            if len(bits) == 0:
                lines.append(f"    assign sum[{col}] = 1'b0;")
                lines.append(f"    assign carry[{col}] = 1'b0;")
            elif len(bits) == 1:
                lines.append(f"    assign sum[{col}] = stage{final_stage}_col{col}[0];")
                lines.append(f"    assign carry[{col}] = 1'b0;")
            else:  # len(bits) == 2
                lines.append(f"    assign sum[{col}] = stage{final_stage}_col{col}[0];")
                lines.append(
                    f"    assign carry[{col}] = stage{final_stage}_col{col}[1];"
                )

        lines.append("")
        return lines


def generate_verilog(dadda_gen, output_file=None):
    """
    Convenience function to generate Verilog from a DaddaGenerator

    Args:
        dadda_gen: DaddaGenerator instance
        output_file: Optional output filename. If provided, writes to file.

    Returns:
        str: Complete SystemVerilog module code
    """
    verilog_gen = VerilogGenerator(dadda_gen)
    verilog_code = verilog_gen.generate_module()

    print(output_file)
    if output_file:
        with open(output_file, "w") as f:
            f.write(verilog_code)

    return verilog_code
