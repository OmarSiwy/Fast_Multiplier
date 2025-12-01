from rich.console import Console
import os

# Delete file once at the start
if os.path.exists('bitheap.txt'):
    os.remove('bitheap.txt')

def visualize_before_after_rich(before_heap, after_heap, stage_num, target_height,
                                fa_input_map, ha_input_map, circuit_summary,
                                width):
    console = Console(record=True,soft_wrap=True)

    _visualize_before_after_rich(before_heap, after_heap, stage_num, target_height,
                            fa_input_map, ha_input_map, circuit_summary, width,
                            console=console)
    # Export everything as plain text (no colors)
    text_output = console.export_text(styles=True)

    # Save to file
    with open("bitheap.txt", "a") as f:
        f.write(text_output)

def _visualize_before_after_rich(before_heap, after_heap, stage_num, target_height,
                                fa_input_map, ha_input_map, circuit_summary,
                                width, console):
    """Pretty print before/after bit heap violetuction with aligned columns and spaces."""
    max_h = max(before_heap.max_height(), after_heap.max_height())

    # Determine column width dynamically
    col_width = width * 2 - 1  # each dot + space between columns

    console.print(f"\n[bold]violetuction Stage {stage_num}[/bold] (target height: {target_height})")
    console.print("[blue]●[/blue] = FA inputs (3 bits)   [violet]●[/violet] = HA inputs (2 bits)\n")

    # Header
    console.print(f"{'h':>3}   {'BEFORE':^{col_width}}    {'AFTER':^{col_width}}")

    # Heap rows
    for h in range(max_h - 1, -1, -1):
        # BEFORE heap
        before_row = " ".join(
            "[blue]●[/blue]" if (col_idx, h) in fa_input_map else
            "[violet]●[/violet]" if (col_idx, h) in ha_input_map else
            "●" if h < len(before_heap.heap[col_idx]) else " "
            for col_idx in reversed(range(width))
        )

        # AFTER heap
        after_row = " ".join(
            "●" if h < len(after_heap.heap[col_idx]) else " "
            for col_idx in reversed(range(width))
        )

        console.print(f"{h:>3}   {before_row:<{col_width}}    {after_row:<{col_width}}")

    # Counts row
    before_counts = " ".join(str(len(before_heap.heap[col_idx])) for col_idx in
                             reversed(range(width)))
    after_counts  = " ".join(str(len(after_heap.heap[col_idx])) for col_idx in
                             reversed(range(width)))
    console.print(f"{'cnt':>3}   {before_counts:<{col_width}}    {after_counts:<{col_width}}")

    # FA/HA summary
    print("\n[bold]FA/HA Cells:[/bold]")
    for line in circuit_summary:
        print(line)

