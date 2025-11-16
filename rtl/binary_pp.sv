module binary_pp #(
    parameter W    = 16,
    parameter PIPE = 0
) (
    // Only used if PIPE = 1
    input logic clk,
    input logic rst,

    input  logic [W-1:0] y,           // Multiplicand 
    input  logic         binary_bit,  // 1 to multiply by Y, 0 to multiply by 0
    output logic [  W:0] pp           // Partial Product Output
);
  localparam TOTAL_WIDTH = W + 1;
  logic [W:0] pp_comb;

  always_comb begin
    if (binary_bit) begin // sign-extend
      pp_comb = {{1{y[W-1]}}, y};
    end else begin // zero
      pp_comb = TOTAL_WIDTH'b0;
    end
  end

  // Optional pipeline stage
  generate
    if (PIPE == 1) begin : gen_pipe
      always_ff @(posedge clk or posedge rst) begin
        if (rst) pp <= {(W + 1) {1'b0}};
        else pp <= pp_comb;
      end
    end else begin : gen_comb
      assign pp = pp_comb;
    end
  endgenerate

endmodule
