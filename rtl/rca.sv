module rca #(
    parameter int W = 8,
    parameter int M = 0,  // Placeholder so doesn't error
    parameter bit PIPE = 0
) (
    input  logic         clk,
    input  logic         rst,
    input  logic [W-1:0] a,
    input  logic [W-1:0] b,
    input  logic         c_in,
    output logic [W-1:0] s,
    output logic         c_out
);
  logic [  W:0] carry;
  logic [W-1:0] sum_comb;
  logic [W-1:0] b_xor;  // XOR b with c_in for subtraction

  // When c_in=1, this implements subtraction: a + ~b + 1
  // When c_in=0, this implements addition: a + b + 0
  assign b_xor = b ^ {W{c_in}};
  assign carry[0] = c_in;

  // Generate W full adders in a ripple chain
  genvar i;
  generate
    for (i = 0; i < W; i++) begin : rca_stage
      fa fa_inst (
          .a(a[i]),
          .b(b_xor[i]),
          .c_in(carry[i]),
          .s(sum_comb[i]),
          .c_out(carry[i+1])
      );
    end
  endgenerate

  // Optional pipeline stage
  generate
    if (PIPE) begin : pipelined
      always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
          s <= '0;
          c_out <= 1'b0;
        end else begin
          s <= sum_comb;
          c_out <= carry[W];
        end
      end
    end else begin : combinational
      assign s = sum_comb;
      assign c_out = carry[W];
    end
  endgenerate

endmodule
