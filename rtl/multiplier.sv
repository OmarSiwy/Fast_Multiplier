module multiplier #(parameter W = 4, parameter PIPE = 0, parameter M = 1)(
    input  logic clk, rst,
    input  logic [W-1:0] a, b,
    output logic [2*W-1:0] product
);
    localparam PROD_W = 2 * W;
    localparam NUM_PP = 4;
    localparam int PP_STAGES = (M > 0) ? 1 : 0;
    localparam int OUTPUT_STAGES = (M > 1) ? 1 : 0;
    localparam int NUM_COMP_STAGES = 2;
    localparam int COMPRESSOR_STAGES = PIPE ? NUM_COMP_STAGES : 0;
    localparam int PREFIX_STAGES = 0;
    localparam int TOTAL_LATENCY = PP_STAGES + COMPRESSOR_STAGES + PREFIX_STAGES + OUTPUT_STAGES;

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
