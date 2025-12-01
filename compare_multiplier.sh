#!/bin/bash

set -e

# Default configuration
WIDTH=16
OUTPUT_FILE="comparison_report.txt"
VERBOSE=0
WORK_DIR="/tmp/$$_mult_compare"

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RTL_DIR="$SCRIPT_DIR/rtl"

# Parse command line arguments
while getopts "w:o:vh" opt; do
    case $opt in
        w) WIDTH="$OPTARG" ;;
        o) OUTPUT_FILE="$OPTARG" ;;
        v) VERBOSE=1 ;;
        h)
            echo "Usage: $0 [-w width] [-o output] [-v] [-h]"
            echo ""
            echo "Compare multiplier configurations using Yosys"
            echo ""
            echo "Options:"
            echo "  -w WIDTH   Bit width (default: 16)"
            echo "  -o OUTPUT  Output report file (default: comparison_report.txt)"
            echo "  -v         Verbose output"
            echo "  -h         Show this help"
            exit 0
            ;;
        \?) echo "Invalid option: -$OPTARG" >&2; exit 1 ;;
    esac
done

# Create work directory
mkdir -p "$WORK_DIR"

# Check for yosys
if ! command -v yosys &> /dev/null; then
    echo "ERROR: yosys is not installed or not in PATH"
    exit 1
fi

# Results arrays
declare -A CELLS
declare -A WIRES
declare -A LTP

log() {
    if [ "$VERBOSE" -eq 1 ]; then
        echo "[INFO] $1"
    fi
}

# Extract LTP cleanly
extract_ltp() {
    local log_file="$1"
    grep "Longest topological path" "$log_file" 2>/dev/null | head -1 | grep -oP 'length=\K[0-9]+' || echo "N/A"
}

echo "=========================================="
echo "Multiplier Comparison using Yosys"
echo "Width: $WIDTH bits"
echo "=========================================="
echo ""

# ============================================
# 1. Yosys Built-in Multiplier (baseline)
# ============================================
echo "=== Yosys Built-in Multiplier (using * operator) ==="

# Signed multiplier
log_file="$WORK_DIR/yosys_mult_signed.log"
yosys -p "
read_verilog -sv $RTL_DIR/yosys_multiplier.sv
hierarchy -top yosys_multiplier -chparam W $WIDTH -chparam SIGNED 1
proc; opt; techmap; opt
stat
flatten
ltp
" > "$log_file" 2>&1 || echo "  Signed: FAILED"

CELLS["yosys_signed"]=$(grep "Number of cells:" "$log_file" | tail -1 | awk '{print $NF}')
LTP["yosys_signed"]=$(extract_ltp "$log_file")
echo "  Signed ${WIDTH}x${WIDTH}: Cells=${CELLS[yosys_signed]}, LTP=${LTP[yosys_signed]}"

# Unsigned multiplier
log_file="$WORK_DIR/yosys_mult_unsigned.log"
yosys -p "
read_verilog -sv $RTL_DIR/yosys_multiplier.sv
hierarchy -top yosys_multiplier -chparam W $WIDTH -chparam SIGNED 0
proc; opt; techmap; opt
stat
flatten
ltp
" > "$log_file" 2>&1 || echo "  Unsigned: FAILED"

CELLS["yosys_unsigned"]=$(grep "Number of cells:" "$log_file" | tail -1 | awk '{print $NF}')
LTP["yosys_unsigned"]=$(extract_ltp "$log_file")
echo "  Unsigned ${WIDTH}x${WIDTH}: Cells=${CELLS[yosys_unsigned]}, LTP=${LTP[yosys_unsigned]}"

# ============================================
# 2. Adder Comparison (for final addition stage)
# ============================================
echo ""
echo "=== Final Adder Comparison (${WIDTH}*2 = $((WIDTH*2)) bits) ==="

# RCA
log_file="$WORK_DIR/rca.log"
yosys -p "
read_verilog -sv $RTL_DIR/fa.sv $RTL_DIR/ha.sv $RTL_DIR/rca.sv
hierarchy -top rca -chparam W $((WIDTH * 2))
proc; opt; techmap; opt
stat
flatten
ltp
" > "$log_file" 2>&1
CELLS["rca"]=$(grep "Number of cells:" "$log_file" | tail -1 | awk '{print $NF}')
LTP["rca"]=$(extract_ltp "$log_file")
echo "  RCA: Cells=${CELLS[rca]}, LTP=${LTP[rca]}"

# CLA
log_file="$WORK_DIR/cla.log"
yosys -p "
read_verilog -sv $RTL_DIR/fa.sv $RTL_DIR/ha.sv $RTL_DIR/gpk.sv $RTL_DIR/rca.sv $RTL_DIR/cla.sv
hierarchy -top cla -chparam W $((WIDTH * 2))
proc; opt; techmap; opt
stat
flatten
ltp
" > "$log_file" 2>&1
CELLS["cla"]=$(grep "Number of cells:" "$log_file" | tail -1 | awk '{print $NF}')
LTP["cla"]=$(extract_ltp "$log_file")
echo "  CLA: Cells=${CELLS[cla]}, LTP=${LTP[cla]}"

# CSA
log_file="$WORK_DIR/csa.log"
yosys -p "
read_verilog -sv $RTL_DIR/fa.sv $RTL_DIR/ha.sv $RTL_DIR/rca.sv $RTL_DIR/csa.sv
hierarchy -top csa -chparam W $((WIDTH * 2))
proc; opt; techmap; opt
stat
flatten
ltp
" > "$log_file" 2>&1
CELLS["csa"]=$(grep "Number of cells:" "$log_file" | tail -1 | awk '{print $NF}')
LTP["csa"]=$(extract_ltp "$log_file")
echo "  CSA: Cells=${CELLS[csa]}, LTP=${LTP[csa]}"

# ============================================
# 3. Prefix Tree Comparison
# ============================================
echo ""
echo "=== Prefix Tree Comparison ($((WIDTH*2)) bits) ==="

PREFIX_ALGS=("kogge-stone" "brent-kung" "sklansky")
for prefix in "${PREFIX_ALGS[@]}"; do
    config_name="prefix_${prefix}"
    config_dir="$WORK_DIR/$config_name"
    mkdir -p "$config_dir"

    echo -n "  $prefix: "

    # Generate prefix tree
    python3 scripts/prefix_tree.py -w $((WIDTH * 2)) --technique "$prefix" --verilog -o "$config_dir/prefix_tree.sv" > /dev/null 2>&1 || {
        echo "FAILED (generation)"
        continue
    }

    # Synthesize
    log_file="$WORK_DIR/${config_name}.log"
    yosys -p "
read_verilog -sv $RTL_DIR/prefix_cell.sv $config_dir/prefix_tree.sv
hierarchy -top prefix_tree
proc; opt; techmap; opt
stat
flatten
ltp
" > "$log_file" 2>&1 || {
        echo "FAILED (synthesis)"
        continue
    }

    CELLS["$config_name"]=$(grep "Number of cells:" "$log_file" | tail -1 | awk '{print $NF}')
    LTP["$config_name"]=$(extract_ltp "$log_file")

    echo "Cells=${CELLS[$config_name]}, LTP=${LTP[$config_name]}"
done

# ============================================
# 4. Partial Product Generators
# ============================================
echo ""
echo "=== Partial Product Generators (single PP, ${WIDTH} bits) ==="

# Binary PP (simple AND)
log_file="$WORK_DIR/binary_pp.log"
yosys -p "
read_verilog -sv $RTL_DIR/binary_pp.sv
hierarchy -top binary_pp -chparam W $WIDTH
proc; opt; techmap; opt
stat
" > "$log_file" 2>&1
CELLS["binary_pp"]=$(grep "Number of cells:" "$log_file" | tail -1 | awk '{print $NF}')
echo "  Binary PP: Cells=${CELLS[binary_pp]} (per partial product)"

# Booth PP (radix-4)
log_file="$WORK_DIR/booth_pp.log"
yosys -p "
read_verilog -sv $RTL_DIR/booth_pp.sv
hierarchy -top booth_pp -chparam W $WIDTH
proc; opt; techmap; opt
stat
" > "$log_file" 2>&1
CELLS["booth_pp"]=$(grep "Number of cells:" "$log_file" | tail -1 | awk '{print $NF}')
echo "  Booth PP: Cells=${CELLS[booth_pp]} (per partial product)"

# ============================================
# 5. Estimate Full Multiplier Costs
# ============================================
echo ""
echo "=== Estimated Full Multiplier Costs ==="

# Binary: W partial products, each W bits
binary_pp_total=$((${CELLS[binary_pp]} * WIDTH))
echo "  Binary encoding: $WIDTH PPs × ${CELLS[binary_pp]} cells = $binary_pp_total cells (PP only)"

# Booth: (W+1)/2 partial products, each W+1 bits
num_booth_pp=$(( (WIDTH + 1) / 2 ))
booth_pp_total=$((${CELLS[booth_pp]} * num_booth_pp))
echo "  Booth encoding: $num_booth_pp PPs × ${CELLS[booth_pp]} cells = $booth_pp_total cells (PP only)"

# ============================================
# Generate Report
# ============================================
echo ""
echo "=========================================="
echo "Generating Report..."
echo "=========================================="

{
    echo "Multiplier Comparison Report"
    echo "============================"
    echo "Width: $WIDTH bits"
    echo "Product Width: $((WIDTH * 2)) bits"
    echo "Date: $(date)"
    echo ""
    echo "=== Yosys Built-in Multiplier (Baseline) ==="
    echo "This uses the Verilog * operator, which Yosys synthesizes"
    echo "using its internal algorithms."
    echo ""
    printf "%-25s | %-10s | %-10s\n" "Type" "Cells" "LTP"
    echo "--------------------------+------------+-----------"
    printf "%-25s | %-10s | %-10s\n" "Signed ${WIDTH}x${WIDTH}" "${CELLS[yosys_signed]:-N/A}" "${LTP[yosys_signed]:-N/A}"
    printf "%-25s | %-10s | %-10s\n" "Unsigned ${WIDTH}x${WIDTH}" "${CELLS[yosys_unsigned]:-N/A}" "${LTP[yosys_unsigned]:-N/A}"

    echo ""
    echo "=== Final Adder Options ($((WIDTH*2)) bits) ==="
    printf "%-25s | %-10s | %-10s\n" "Adder Type" "Cells" "LTP"
    echo "--------------------------+------------+-----------"
    printf "%-25s | %-10s | %-10s\n" "RCA (Ripple-Carry)" "${CELLS[rca]:-N/A}" "${LTP[rca]:-N/A}"
    printf "%-25s | %-10s | %-10s\n" "CLA (Carry-Lookahead)" "${CELLS[cla]:-N/A}" "${LTP[cla]:-N/A}"
    printf "%-25s | %-10s | %-10s\n" "CSA (Carry-Select)" "${CELLS[csa]:-N/A}" "${LTP[csa]:-N/A}"

    echo ""
    echo "=== Prefix Tree Options ($((WIDTH*2)) bits) ==="
    printf "%-25s | %-10s | %-10s\n" "Algorithm" "Cells" "LTP"
    echo "--------------------------+------------+-----------"
    for prefix in "${PREFIX_ALGS[@]}"; do
        key="prefix_${prefix}"
        printf "%-25s | %-10s | %-10s\n" "$prefix" "${CELLS[$key]:-N/A}" "${LTP[$key]:-N/A}"
    done

    echo ""
    echo "=== Partial Product Generation ==="
    printf "%-25s | %-10s | %-15s\n" "Encoding" "Cells/PP" "Total PPs"
    echo "--------------------------+------------+----------------"
    printf "%-25s | %-10s | %-15s\n" "Binary (radix-2)" "${CELLS[binary_pp]:-N/A}" "$WIDTH"
    printf "%-25s | %-10s | %-15s\n" "Booth (radix-4)" "${CELLS[booth_pp]:-N/A}" "$num_booth_pp"
} | tee "$OUTPUT_FILE"

echo ""
echo "Report saved to: $OUTPUT_FILE"

# Cleanup
if [ "$VERBOSE" -eq 0 ]; then
    rm -rf "$WORK_DIR"
fi

echo ""
echo "Done!"
