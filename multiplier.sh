#!/bin/zsh
# Multiplier RTL Generator Script
# Usage: ./multiplier.sh W=<width> ENCODING=<binary|booth> COMPRESSOR_ALGORITHM=<dadda|bickerstaff|faonly> \
#        PREFIX_ALGORITHM=<kogge-stone|brent-kung|sklansky> FINAL_ADDER=<xor> M=<pipeline_stages> PIPE=<pipelining_level> -DSIGNED=<0|1>

# Parse command line arguments
for arg in "$@"; do
    case $arg in
        W=*)
            W="${arg#*=}"
            ;;
        ENCODING=*)
            ENCODING="${arg#*=}"
            ;;
        COMPRESSOR_ALGORITHM=*)
            COMPRESSOR_ALGORITHM="${arg#*=}"
            ;;
        PREFIX_ALGORITHM=*)
            PREFIX_ALGORITHM="${arg#*=}"
            ;;
        FINAL_ADDER=*)
            FINAL_ADDER="${arg#*=}"
            ;;
        M=*)
            M="${arg#*=}"
            ;;
        PIPE=*)
            PIPE="${arg#*=}"
            ;;
        *)
        SIGNED=*)
            SIGNED="${arg#*=}"
            ;;
        *)
            echo "Unknown parameter: $arg"
            ;;
    esac
done

# Set defaults if not provided
W=${W:-16}
ENCODING=${ENCODING:-binary}
COMPRESSOR_ALGORITHM=${COMPRESSOR_ALGORITHM:-dadda}
PREFIX_ALGORITHM=${PREFIX_ALGORITHM:-kogge-stone}
FINAL_ADDER=${FINAL_ADDER:-xor}
M=${M:-0}
PIPE=${PIPE:-0}
SIGNED=${SIGNED:-0}

# Validate parameters
if [[ ! "$ENCODING" =~ ^(binary|booth)$ ]]; then
    echo "Error: ENCODING must be 'binary' or 'booth'"
    exit 1
fi

if [[ ! "$COMPRESSOR_ALGORITHM" =~ ^(dadda|bickerstaff|faonly)$ ]]; then
    echo "Error: COMPRESSOR_ALGORITHM must be 'dadda', 'bickerstaff', or 'faonly'"
    exit 1
fi

if [[ ! "$PREFIX_ALGORITHM" =~ ^(kogge-stone|brent-kung|sklansky)$ ]]; then
    echo "Error: PREFIX_ALGORITHM must be 'kogge-stone', 'brent-kung', or 'sklansky'"
    exit 1
fi

# Display configuration
echo "=========================================="
echo "Multiplier Generator Configuration"
echo "=========================================="
echo "Width (W):               $W"
echo "Encoding:                $ENCODING"
echo "Compressor Algorithm:    $COMPRESSOR_ALGORITHM"
echo "Prefix Algorithm:        $PREFIX_ALGORITHM"
echo "Final Adder:             $FINAL_ADDER"
echo "Pipeline Stages (M):     $M"
echo "Pipelining Level (PIPE): $PIPE"
echo "=========================================="

# Create necessary directories
mkdir -p rtl
mkdir -p data
mkdir -p tb

# Determine number of partial products
if [[ "$ENCODING" == "booth" ]]; then
    NUM_PP=$(( (W + 1) / 2 ))
else
    NUM_PP=$W
fi

echo ""
echo "Step 1: Generating Compressor Tree..."
if [[ "$SIGNED" -eq 1 ]]; then
    python3 compressor_tree.py \
        -w $W \
        -n $NUM_PP \
        -e $ENCODING \
        -a $COMPRESSOR_ALGORITHM \
        -o rtl/compressor_tree.sv \
        -r tb/ \
        --algorithm $COMPRESSOR_ALGORITHM \
        -s
else
    python3 compressor_tree.py \
        -w $W \
        -n $NUM_PP \
        -e $ENCODING \
        -a $COMPRESSOR_ALGORITHM \
        -o rtl/compressor_tree.sv \
        -r tb/ \
        --unsigned \
        -s
fi

if [ $? -ne 0 ]; then
    echo "Error: Compressor tree generation failed"
    exit 1
fi

echo ""
echo "Step 2: Generating Prefix Tree..."
python3 prefix_tree.py \
    -w $((W * 2)) \
    --technique $PREFIX_ALGORITHM \
    --pipeline 0 \
    --verilog \
    -o rtl/prefix_tree.sv \
    --stats

if [ $? -ne 0 ]; then
    echo "Error: Prefix tree generation failed"
    exit 1
fi

echo ""
echo "Step 4: Generating Multiplier Top Module..."

# Determine partial product width based on encoding
# Booth: W+1 bits (sign bit + W bits)
# Binary: W bits (compressor_tree expects W bits for binary)
if [[ "$ENCODING" == "booth" ]]; then
    PP_WIDTH=$((W + 1))
else
    PP_WIDTH=$W
fi

# Generate multiplier.sv
cat > rtl/multiplier.sv << EOF
//
// Multiplier Top Module
// Width: ${W}-bit
// Encoding: ${ENCODING}
// Compressor: ${COMPRESSOR_ALGORITHM}
// Prefix Tree: ${PREFIX_ALGORITHM}
// Final Adder: ${FINAL_ADDER}
// Pipeline Stages (M): ${M}
// Pipelining Level (PIPE): ${PIPE}
//

module multiplier #(
    parameter W = ${W},
    parameter PIPE = ${PIPE},
    parameter M = ${M}
)(
    input  logic clk,
    input  logic rst,
    input  logic [W-1:0] a,
    input  logic [W-1:0] b,
    output logic [2*W-1:0] product
);

    localparam PROD_W = 2 * W;
    localparam NUM_PP = ${NUM_PP};

EOF

if [[ "$ENCODING" == "booth" ]]; then
    cat >> rtl/multiplier.sv << 'EOF'
    // Booth encoding: PP_WIDTH = W+1
    localparam PP_WIDTH = W + 1;

    // Packed 2D array matching compressor_tree interface
    logic [NUM_PP-1:0][PP_WIDTH-1:0] pp_packed;
    logic [NUM_PP-1:0][PP_WIDTH-1:0] pp_packed_pipe;

    /* verilator lint_off ASCRANGE */
    logic [0:NUM_PP-2] cpl;
    logic [0:NUM_PP-2] cpl_pipe;
    /* verilator lint_on ASCRANGE */

    // Generate partial products and pack
    genvar i;
    generate
        for (i = 0; i < NUM_PP; i++) begin : gen_booth_pp
            booth_pp #(.W(W), .PIPE(0)) booth_inst (
                .clk(clk),
                .rst(rst),
                .y(a),
                .booth_bits({(i == NUM_PP-1) ? 1'b0 : b[2*i+2], b[2*i+1], b[2*i], (i == 0) ? 1'b0 : b[2*i-1]}),
                .pp(pp_packed[i]),
                .cpl((i < NUM_PP-1) ? cpl[i] : 1'b0)
            );
        end
    endgenerate

    // Pipeline registers (if M > 0)
    generate
        if (M > 0) begin : gen_pp_pipeline
            always_ff @(posedge clk) begin
                if (rst) begin
                    pp_packed_pipe <= '0;
                    cpl_pipe <= '0;
                end else begin
                    pp_packed_pipe <= pp_packed;
                    cpl_pipe <= cpl;
                end
            end
        end
    endgenerate

    // Compressor tree outputs
    logic [PROD_W-1:0] sum, carry;

    // Instantiate compressor tree
    generate
        if (M > 0) begin : gen_comp_pipeline
            compressor_tree #(.PIPE(PIPE)) comp_tree (
                .clk(clk),
                .rst(rst),
                .pp(pp_packed_pipe),
                .cpl(cpl_pipe),
                .sum(sum),
                .carry(carry)
            );
        end else begin : gen_comp_no_pipeline
            compressor_tree #(.PIPE(PIPE)) comp_tree (
                .clk(clk),
                .rst(rst),
                .pp(pp_packed),
                .cpl(cpl),
                .sum(sum),
                .carry(carry)
            );
        end
    endgenerate
EOF
else
    cat >> rtl/multiplier.sv << 'EOF'
    // Binary encoding
    // binary_pp outputs W+1 bits, compressor_tree expects W bits

    // Intermediate signals: W+1 bits from binary_pp
    logic [W:0] pp_full [0:NUM_PP-1];

    // Packed 2D array matching compressor_tree interface
    logic [NUM_PP-1:0][W-1:0] pp_packed;
    logic [NUM_PP-1:0][W-1:0] pp_packed_pipe;

    // Generate partial products and pack
    genvar i;
    generate
        for (i = 0; i < NUM_PP; i++) begin : gen_binary_pp
            binary_pp #(.W(W), .PIPE(0)) binary_inst (
                .clk(clk),
                .rst(rst),
                .y(a),
                .binary_bit(b[i]),
                .pp(pp_full[i])  // Get W+1 bits
            );

            // Truncate and pack into 2D array
            assign pp_packed[i] = pp_full[i][W-1:0];
        end
    endgenerate

    // Pipeline registers (if M > 0)
    generate
        if (M > 0) begin : gen_pp_pipeline
            always_ff @(posedge clk) begin
                if (rst)
                    pp_packed_pipe <= '0;
                else
                    pp_packed_pipe <= pp_packed;
            end
        end
    endgenerate

    // Compressor tree outputs
    logic [PROD_W-1:0] sum, carry;

    // Instantiate compressor tree
    generate
        if (M > 0) begin : gen_comp_pipeline
            compressor_tree #(.PIPE(PIPE)) comp_tree (
                .clk(clk),
                .rst(rst),
                .pp(pp_packed_pipe),
                .sum(sum),
                .carry(carry)
            );
        end else begin : gen_comp_no_pipeline
            compressor_tree #(.PIPE(PIPE)) comp_tree (
                .clk(clk),
                .rst(rst),
                .pp(pp_packed),
                .sum(sum),
                .carry(carry)
            );
        end
    endgenerate
EOF
fi

# Add final adder and pipelining logic
cat >> rtl/multiplier.sv << 'EOF'

    // Final addition: product = sum + carry
    logic [PROD_W-1:0] final_sum;
    assign final_sum = sum + carry;

    // Pipeline output if M > 1
    generate
        if (M > 1) begin : gen_output_pipeline
            logic [PROD_W-1:0] product_reg;

            always_ff @(posedge clk) begin
                if (rst)
                    product_reg <= '0;
                else
                    product_reg <= final_sum;
            end

            assign product = product_reg;
        end else begin : gen_output_no_pipeline
            assign product = final_sum;
        end
    endgenerate

endmodule
EOF

echo ""
echo "=========================================="
echo "Generation Complete!"
echo "=========================================="
echo "Generated files:"
echo "  - rtl/compressor_tree.sv"
echo "  - rtl/prefix_tree.sv"
echo "  - rtl/multiplier.sv"
echo ""
echo "Configuration:"
echo "  Width: ${W}-bit"
echo "  Partial Products: ${NUM_PP}"
if [[ "$ENCODING" == "booth" ]]; then
    echo "  PP Generator Width: $((W + 1)) (booth_pp output)"
    echo "  PP Compressor Width: $((W + 1)) (compressor_tree input)"
else
    echo "  PP Generator Width: $((W + 1)) (binary_pp output)"
    echo "  PP Compressor Width: ${W} (compressor_tree input - truncated)"
fi
echo "  Product Width: $((W * 2))"
echo "=========================================="
