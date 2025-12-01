#!/usr/bin/env python3
"""
Graphviz DOT Generator for Dadda/Bickerstaff Compressor Trees
Layout: MSB (high columns) on LEFT, LSB (column 0) on RIGHT
"""

class GraphvizGenerator:
    def __init__(self, dadda_gen, show_final_adder=False):
        """
        Initialize with a DaddaGenerator instance

        Args:
            dadda_gen: DaddaGenerator object containing stages, FA/HA instances, etc.
            show_final_adder: If True, show final adder stage after sum/carry outputs
        """
        self.gen = dadda_gen
        self.w = dadda_gen.w
        self.prod_width = dadda_gen.prod_width
        self.num_pp = dadda_gen.num_pp
        self.num_stages = dadda_gen.num_stages
        self.stages = dadda_gen.stages
        self.fa_instances = dadda_gen.fa_instances
        self.ha_instances = dadda_gen.ha_instances
        self.encoding = dadda_gen.encoding
        self.unsigned = dadda_gen.unsigned
        self.algorithm = dadda_gen.algorithm
        self.show_final_adder = show_final_adder

    def generate_dot(self):
        """Generate a Graphviz DOT diagram showing the compressor tree"""
        lines = []

        lines.extend(self._generate_header())

        node_id = 0
        stage_nodes = []

        # Stage 0: Initial Partial Products
        node_id, stage0_nodes = self._generate_stage0(node_id, lines)
        stage_nodes.append(stage0_nodes)

        # Process each reduction stage
        for stage_idx in range(self.num_stages):
            node_id, stage_nodes_current = self._generate_reduction_stage(
                stage_idx, node_id, stage_nodes, lines
            )
            stage_nodes.append(stage_nodes_current)

        # Final adder and outputs
        self._generate_final_stage(node_id, stage_nodes, lines)

        lines.append("}")
        return "\n".join(lines)

    def _generate_header(self):
        """Generate DOT file header and styling"""
        return [
            "digraph DaddaTree {",
            "  rankdir=TB;",
            "  ranksep=2.0;",
            "  nodesep=0.5;",
            "  splines=curved;",
            "  node [shape=box, style=filled, width=2.8, height=2.8, fontsize=44];",
            "  edge [penwidth=3.0, arrowsize=2.0];",
            "  ",
            "  // Styling",
            "  node [fontname=\"Arial\"];",
            "  edge [fontname=\"Arial\", fontsize=10];",
            "  newrank=true;",
            "  ",
            "  // Layout: MSB (high columns) on LEFT, LSB (column 0) on RIGHT",
            ""
        ]

    def _generate_stage0(self, node_id, lines):
        """Generate Stage 0 nodes (initial partial products)"""
        lines.extend([
            "  // Stage 0: Initial Partial Products",
            "  {",
            "    rank=same;"
        ])

        stage0_nodes = [[] for _ in range(self.prod_width)]
        all_nodes_in_order = []

        # Iterate from high to low column (MSB to LSB)
        # This places MSB on left, LSB on right in the visualization
        for col in range(self.prod_width - 1, -1, -1):
            for bit_idx, (bit_name, bit_type) in enumerate(self.stages[0].heap[col]):
                node_name = f"n{node_id}"
                lines.append(f"    {node_name} [label=\"{bit_name}\", fillcolor=\"lightgray\"];")
                stage0_nodes[col].append((node_name, 'normal'))
                all_nodes_in_order.append(node_name)
                node_id += 1

        lines.extend([
            "  }",
            ""
        ])

        # Add invisible edges to force left-to-right ordering
        if len(all_nodes_in_order) > 1:
            lines.append("  // Force left-to-right ordering in Stage 0")
            for i in range(len(all_nodes_in_order) - 1):
                lines.append(f"  {all_nodes_in_order[i]} -> {all_nodes_in_order[i+1]} [style=invis, weight=10];")
            lines.append("")

        return node_id, stage0_nodes

    def _generate_reduction_stage(self, stage_idx, node_id, stage_nodes, lines):
        """Generate a single reduction stage with FA/HA nodes"""
        lines.extend([
            f"  // Stage {stage_idx + 1}: Reduction",
            f"  {{",
            f"    rank=same;"
        ])

        stage_nodes_current = [[] for _ in range(self.prod_width)]
        all_nodes_in_order = []

        # Get FA and HA instances for this stage
        stage_fas = [(col, idx) for s, col, idx, inputs in self.fa_instances if s == stage_idx]
        stage_has = [(col, idx) for s, col, idx, inputs in self.ha_instances if s == stage_idx]

        # Track nodes created for each column
        fa_nodes_created = {}
        ha_nodes_created = {}

        for col in range(self.prod_width):
            fa_nodes_created[col] = []
            ha_nodes_created[col] = []

        # Create FA nodes - iterate from high to low column for left-to-right layout
        for col, idx in sorted(stage_fas, key=lambda x: -x[0]):
            fa_node = f"n{node_id}"
            lines.append(f"    {fa_node} [label=\"FA\\nc{col}\", fillcolor=\"lightblue\"];")
            fa_nodes_created[col].append(fa_node)
            all_nodes_in_order.append(fa_node)

            stage_nodes_current[col].append((fa_node, 'fa_sum'))
            if col + 1 < self.prod_width:
                stage_nodes_current[col + 1].append((fa_node, 'fa_carry'))

            node_id += 1

        # Create HA nodes - iterate from high to low column for left-to-right layout
        for col, idx in sorted(stage_has, key=lambda x: -x[0]):
            ha_node = f"n{node_id}"
            lines.append(f"    {ha_node} [label=\"HA\\nc{col}\", fillcolor=\"pink\"];")
            ha_nodes_created[col].append(ha_node)
            all_nodes_in_order.append(ha_node)

            stage_nodes_current[col].append((ha_node, 'ha_sum'))
            if col + 1 < self.prod_width:
                stage_nodes_current[col + 1].append((ha_node, 'ha_carry'))

            node_id += 1

        lines.extend([
            "  }",
            ""
        ])

        # Add invisible edges to force left-to-right ordering
        if len(all_nodes_in_order) > 1:
            lines.append(f"  // Force left-to-right ordering in Stage {stage_idx + 1}")
            for i in range(len(all_nodes_in_order) - 1):
                lines.append(f"  {all_nodes_in_order[i]} -> {all_nodes_in_order[i+1]} [style=invis, weight=10];")
            lines.append("")

        # Create edges from previous stage to current stage
        self._generate_stage_edges(stage_idx, stage_nodes, fa_nodes_created,
                                   ha_nodes_created, stage_nodes_current, lines)

        return node_id, stage_nodes_current

    def _generate_stage_edges(self, stage_idx, stage_nodes, fa_nodes_created,
                              ha_nodes_created, stage_nodes_current, lines):
        """Generate edges connecting stages"""
        # Process all columns
        for col in range(self.prod_width):
            prev_bits = stage_nodes[stage_idx][col]

            bits_consumed = 0

            # Connect to FAs
            for fa_node in fa_nodes_created[col]:
                for i in range(3):
                    if bits_consumed < len(prev_bits):
                        input_node, input_type = prev_bits[bits_consumed]
                        if input_type in ['fa_carry', 'ha_carry']:
                            lines.append(f"  {input_node} -> {fa_node} [label=\"c\", color=\"red\"];")
                        else:
                            lines.append(f"  {input_node} -> {fa_node};")
                        bits_consumed += 1

            # Connect to HAs
            for ha_node in ha_nodes_created[col]:
                for i in range(2):
                    if bits_consumed < len(prev_bits):
                        input_node, input_type = prev_bits[bits_consumed]
                        if input_type in ['fa_carry', 'ha_carry']:
                            lines.append(f"  {input_node} -> {ha_node} [label=\"c\", color=\"red\"];")
                        else:
                            lines.append(f"  {input_node} -> {ha_node};")
                        bits_consumed += 1

            # Passthrough bits
            while bits_consumed < len(prev_bits):
                stage_nodes_current[col].append(prev_bits[bits_consumed])
                bits_consumed += 1

    def _generate_final_stage(self, node_id, stage_nodes, lines):
        """Generate sum/carry output nodes and optionally final adder"""
        lines.extend([
            "  // Final Sum/Carry Outputs",
            "  {",
            "    rank=same;"
        ])

        output_nodes = []
        output_nodes_in_order = []
        sum_carry_by_col = {}  # Track sum/carry outputs by column for adder connections
        
        # Create output nodes from high to low column for left-to-right layout
        # Each column gets exactly one s[col] and one c[col] (if it has 2 bits)
        for col in range(self.prod_width - 1, -1, -1):
            final_bits = stage_nodes[-1][col]
            sum_carry_by_col[col] = []
            
            for bit_idx, (node_name, node_type) in enumerate(final_bits):
                output_node = f"n{node_id}"
                
                # Assign first bit to sum, second bit to carry
                if bit_idx == 0:
                    label = f"s[{col}]"
                    color = "yellow"
                else:
                    label = f"c[{col}]"
                    color = "orange"
                
                lines.append(f"    {output_node} [label=\"{label}\", fillcolor=\"{color}\", shape=\"ellipse\"];")
                output_nodes.append((node_name, output_node))
                output_nodes_in_order.append(output_node)
                sum_carry_by_col[col].append(output_node)
                node_id += 1

        lines.extend([
            "  }",
            ""
        ])

        # Add invisible edges to force left-to-right ordering for outputs
        if len(output_nodes_in_order) > 1:
            lines.append("  // Force left-to-right ordering for outputs")
            for i in range(len(output_nodes_in_order) - 1):
                lines.append(f"  {output_nodes_in_order[i]} -> {output_nodes_in_order[i+1]} [style=invis, weight=10];")
            lines.append("")

        # Connect final reduction stage outputs to output nodes
        for source_node, output_node in output_nodes:
            lines.append(f"  {source_node} -> {output_node};")
        
        lines.append("")

        # Optionally add final adder stage
        if self.show_final_adder:
            lines.extend([
                "  // Final Adder",
                "  {",
                "    rank=same;"
            ])

            adder_nodes = []
            adder_nodes_in_order = []
            
            # Create adder nodes from high to low column for left-to-right layout
            for col in range(self.prod_width - 1, -1, -1):
                if len(sum_carry_by_col[col]) > 0:
                    adder_node = f"n{node_id}"
                    lines.append(f"    {adder_node} [label=\"+\\nc{col}\", fillcolor=\"lightgreen\"];")
                    adder_nodes.append((col, adder_node))
                    adder_nodes_in_order.append(adder_node)
                    node_id += 1

            lines.extend([
                "  }",
                ""
            ])

            # Add invisible edges to force left-to-right ordering for adders
            if len(adder_nodes_in_order) > 1:
                lines.append("  // Force left-to-right ordering for adders")
                for i in range(len(adder_nodes_in_order) - 1):
                    lines.append(f"  {adder_nodes_in_order[i]} -> {adder_nodes_in_order[i+1]} [style=invis, weight=10];")
                lines.append("")

            lines.extend([
                "  // Product Outputs",
                "  {",
                "    rank=same;"
            ])

            prod_nodes = []
            prod_nodes_in_order = []
            
            # Create product output nodes from high to low column for left-to-right layout
            for col, adder_node in sorted(adder_nodes, key=lambda x: -x[0]):
                prod_node = f"n{node_id}"
                lines.append(f"    {prod_node} [label=\"P[{col}]\", fillcolor=\"lightcyan\", shape=\"ellipse\"];")
                prod_nodes.append((adder_node, prod_node))
                prod_nodes_in_order.append(prod_node)
                node_id += 1

            lines.extend([
                "  }",
                ""
            ])

            # Add invisible edges to force left-to-right ordering for product outputs
            if len(prod_nodes_in_order) > 1:
                lines.append("  // Force left-to-right ordering for product outputs")
                for i in range(len(prod_nodes_in_order) - 1):
                    lines.append(f"  {prod_nodes_in_order[i]} -> {prod_nodes_in_order[i+1]} [style=invis, weight=10];")
                lines.append("")

            # Connect sum/carry outputs to adders
            for col in range(self.prod_width):
                if col in sum_carry_by_col and len(sum_carry_by_col[col]) > 0:
                    adder_node = [a for c, a in adder_nodes if c == col][0]
                    
                    for sum_carry_node in sum_carry_by_col[col]:
                        lines.append(f"  {sum_carry_node} -> {adder_node};")

            # Carry chain - flows from LSB to MSB (right to left visually)
            adder_nodes_sorted = sorted(adder_nodes, key=lambda x: x[0])   # LSB → MSB

            for i in range(len(adder_nodes_sorted) - 1):
                col_cur, node_cur = adder_nodes_sorted[i]
                col_next, node_next = adder_nodes_sorted[i + 1]

                # Carry flows from col_cur (lower/LSB) to col_next (higher/MSB)
                # Route above the nodes using top ports
                lines.append(
                    f"  {node_cur}:n -> {node_next}:n [label=\"c\", color=\"red\", style=\"dashed\", dir=\"back\"];"
                )

            # Connect adders to product outputs
            for adder_node, prod_node in prod_nodes:
                lines.append(f"  {adder_node} -> {prod_node};")


def generate_graphviz(dadda_gen, output_file='graph.dot', show_final_adder=False):
    """
    Convenience function to generate Graphviz DOT from a DaddaGenerator

    Args:
        dadda_gen: DaddaGenerator instance
        output_file: Output filename for DOT file
        show_final_adder: If True, show final adder stage after sum/carry outputs

    Returns:
        str: DOT file contents
    """
    graphviz_gen = GraphvizGenerator(dadda_gen, show_final_adder=show_final_adder)
    dot_content = graphviz_gen.generate_dot()

    with open(output_file, 'w') as f:
        f.write(dot_content)

    return dot_content


def print_graphviz_instructions(output_file='graph.dot'):
    """Print instructions for generating visualization from DOT file"""
    print("\n" + "="*80)
    print("COMPRESSOR TREE DIAGRAM")
    print("="*80)
    print(f"Graphviz DOT file saved to: {output_file}")
    print("Generate visualization with:")
    print(f"  dot -Tpng {output_file} -o graph.png")
    print(f"  dot -Tsvg {output_file} -o graph.svg")
    print(f"  dot -Tpdf {output_file} -o graph.pdf")
    print()
