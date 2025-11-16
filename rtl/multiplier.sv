//
// Multiplier Top Module
// Width: 4-bit
// Encoding: binary
// Compressor: dadda
// Prefix Tree: kogge-stone
// Final Adder: xor
// Pipeline Stages (M): 2
// Pipelining Level (PIPE): 0
//

module multiplier #(
    parameter W = 4,
    parameter PIPE = 0,
    parameter M = 2
)(
    input  logic clk,
    input  logic rst,
    input  logic [W-1:0] a,
    input  logic [W-1:0] b,
    output logic [2*W-1:0] product
);

    localparam PROD_W = 2 * W;
    localparam NUM_PP = 4;

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
