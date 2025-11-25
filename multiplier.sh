#!/bin/bash
for arg in "$@"; do
    case $arg in
        W=*) W="${arg#*=}" ;;
        ENCODING=*) ENCODING="${arg#*=}" ;;
        COMPRESSOR_ALGORITHM=*) COMPRESSOR_ALGORITHM="${arg#*=}" ;;
        PREFIX_ALGORITHM=*) PREFIX_ALGORITHM="${arg#*=}" ;;
        M=*) M="${arg#*=}" ;;
        PIPE=*) PIPE="${arg#*=}" ;;
        UNSIGNED=*) UNSIGNED="${arg#*=}" ;;
        FINAL_ADDER=*) ;;
        *) ;;
    esac
done

W=${W:-16}
ENCODING=${ENCODING:-binary}
COMPRESSOR_ALGORITHM=${COMPRESSOR_ALGORITHM:-dadda}
PREFIX_ALGORITHM=${PREFIX_ALGORITHM:-kogge-stone}
M=${M:-0}
PIPE=${PIPE:-0}
UNSIGNED=${UNSIGNED:-0}

# Step 1: Generate compressor tree
if [ "$UNSIGNED" -eq 1 ]; then
    python3 compressor_tree.py -w $W -e $ENCODING -a $COMPRESSOR_ALGORITHM -o rtl/compressor_tree.sv -r tb/ --unsigned
else
    python3 compressor_tree.py -w $W -e $ENCODING -a $COMPRESSOR_ALGORITHM -o rtl/compressor_tree.sv -r tb/
fi

# Step 2: Extract parameters
NUM_STAGES=$(grep "Reduction Stages:" rtl/compressor_tree.sv | grep -o "[0-9]*" | head -1)
NUM_PP=$(grep "Partial Products:" rtl/compressor_tree.sv | grep -o "[0-9]*" | head -1)
[ -z "$NUM_PP" ] && NUM_PP=$(( ENCODING == "booth" ? (W + 1) / 2 : W ))

# Step 3: Generate prefix tree
python3 prefix_tree.py -w $((W * 2)) --technique $PREFIX_ALGORITHM --verilog -o rtl/prefix_tree.sv > /dev/null 2>&1

# Step 4: Generate multiplier.sv
mkdir -p rtl
cat > rtl/multiplier.sv << HEADER
module multiplier #(parameter W = $W, parameter PIPE = $PIPE, parameter M = $M)(
    input  logic clk, rst,
    input  logic [W-1:0] a, b,
    output logic [2*W-1:0] product
);
    localparam PROD_W = 2 * W;
    localparam NUM_PP = $NUM_PP;
    localparam int PP_STAGES = (M > 0) ? 1 : 0;
    localparam int OUTPUT_STAGES = (M > 1) ? 1 : 0;
    localparam int NUM_COMP_STAGES = $NUM_STAGES;
    localparam int COMPRESSOR_STAGES = PIPE ? NUM_COMP_STAGES : 0;
    localparam int PREFIX_STAGES = 0;
    localparam int TOTAL_LATENCY = PP_STAGES + COMPRESSOR_STAGES + PREFIX_STAGES + OUTPUT_STAGES;

HEADER

if [ "$ENCODING" = "booth" ]; then
    cat >> rtl/multiplier.sv << 'BOOTH'
    localparam PP_WIDTH = W + 1;
    logic [PP_WIDTH-1:0] pp_individual [NUM_PP-1:0];
    logic cpl_individual [NUM_PP-1:0];
    logic [PP_WIDTH-1:0] pp_packed [NUM_PP-1:0];
    logic [PP_WIDTH-1:0] pp_packed_pipe [NUM_PP-1:0];
    logic [NUM_PP-1:0] cpl, cpl_pipe;

    genvar i;
    generate
        for (i = 0; i < NUM_PP; i++) begin : gen_booth_pp
            booth_pp #(.W(W), .PIPE(0)) booth_inst (
                .clk(clk), .rst(rst), .y(a),
                .booth_bits({(i == NUM_PP-1) ? 1'b0 : b[2*i+2], b[2*i+1], b[2*i], (i == 0) ? 1'b0 : b[2*i-1]}),
                .pp(pp_individual[i]), .cpl(cpl_individual[i])
            );
            assign pp_packed[i] = pp_individual[i];
            assign cpl[i] = cpl_individual[i];
        end
        if (M > 0) begin : gen_pp_pipeline
            always_ff @(posedge clk) begin
                if (rst) begin
                    for (int j = 0; j < NUM_PP; j++) pp_packed_pipe[j] <= '0;
                    cpl_pipe <= '0;
                end else begin
                    for (int j = 0; j < NUM_PP; j++) pp_packed_pipe[j] <= pp_packed[j];
                    cpl_pipe <= cpl;
                end
            end
        end
    endgenerate

    logic [PROD_W-1:0] sum, carry;
    generate
        if (M > 0) begin : gen_comp_pipeline
            compressor_tree #(.PIPE(PIPE)) comp_tree (.clk(clk), .rst(rst), .pp(pp_packed_pipe), .cpl(cpl_pipe), .sum(sum), .carry(carry));
        end else begin : gen_comp_no_pipeline
            compressor_tree #(.PIPE(PIPE)) comp_tree (.clk(clk), .rst(rst), .pp(pp_packed), .cpl(cpl), .sum(sum), .carry(carry));
        end
    endgenerate
BOOTH
else
    cat >> rtl/multiplier.sv << 'BINARY'
    localparam PP_WIDTH = W;
    logic [W:0] pp_individual [NUM_PP-1:0];
    logic [W-1:0] pp_packed [NUM_PP-1:0];
    logic [W-1:0] pp_packed_pipe [NUM_PP-1:0];

    genvar i;
    generate
        for (i = 0; i < NUM_PP; i++) begin : gen_binary_pp
            binary_pp #(.W(W), .PIPE(0)) binary_inst (.clk(clk), .rst(rst), .y(a), .binary_bit(b[i]), .pp(pp_individual[i]));
            assign pp_packed[i] = pp_individual[i][W-1:0];
        end
        if (M > 0) begin : gen_pp_pipeline
            always_ff @(posedge clk) begin
                if (rst) begin
                    for (int j = 0; j < NUM_PP; j++) pp_packed_pipe[j] <= '0;
                end else begin
                    for (int j = 0; j < NUM_PP; j++) pp_packed_pipe[j] <= pp_packed[j];
                end
            end
        end
    endgenerate

    logic [PROD_W-1:0] sum, carry;
    generate
        if (M > 0) begin : gen_comp_pipeline
            compressor_tree #(.PIPE(PIPE)) comp_tree (.clk(clk), .rst(rst), .pp(pp_packed_pipe), .sum(sum), .carry(carry));
        end else begin : gen_comp_no_pipeline
            compressor_tree #(.PIPE(PIPE)) comp_tree (.clk(clk), .rst(rst), .pp(pp_packed), .sum(sum), .carry(carry));
        end
    endgenerate
BINARY
fi

cat >> rtl/multiplier.sv << 'FOOTER'

    logic [PROD_W-1:0] final_sum;
    assign final_sum = sum + carry;

    generate
        if (M > 1) begin : gen_output_pipeline
            logic [PROD_W-1:0] product_reg;
            always_ff @(posedge clk) begin
                if (rst) product_reg <= '0;
                else product_reg <= final_sum;
            end
            assign product = product_reg;
        end else begin : gen_output_no_pipeline
            assign product = final_sum;
        end
    endgenerate

endmodule
FOOTER
