module csa #(
    parameter int W = 8,
    parameter int M = 4,
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

  localparam int NUM_BLOCKS = (W + M - 1) / M;  // Ceiling division

  logic [W-1:0] sum_comb;
  logic [NUM_BLOCKS-1:0] carry_out0, carry_out1;  // Carry outputs for c_in=0 and c_in=1
  logic [NUM_BLOCKS:0] block_carry_sel;  // Selected carry chain
  logic [       W-1:0] b_xor;  // XOR b with c_in for subtraction

  // When c_in=1, this implements subtraction: a + ~b + 1
  // When c_in=0, this implements addition: a + b + 0
  assign b_xor = b ^ {W{c_in}};
  assign block_carry_sel[0] = c_in;

  // Generate carry-select blocks
  genvar i, j;
  generate
    for (i = 0; i < NUM_BLOCKS; i++) begin : csa_blocks
      localparam int BLOCK_START = i * M;
      localparam int BLOCK_END = (i * M + M) > W ? W : (i * M + M);
      localparam int BLOCK_SIZE = BLOCK_END - BLOCK_START;

      // Two parallel adders: one assuming carry_in=0, one assuming carry_in=1
      logic [BLOCK_SIZE-1:0] sum0, sum1;
      logic [BLOCK_SIZE:0] carry_chain0, carry_chain1;

      assign carry_chain0[0] = 1'b0;
      assign carry_chain1[0] = 1'b1;

      // Generate adders for both carry assumptions
      for (j = 0; j < BLOCK_SIZE; j++) begin : dual_adders
        fa fa0 (
            .a(a[BLOCK_START+j]),
            .b(b_xor[BLOCK_START+j]),
            .c_in(carry_chain0[j]),
            .s(sum0[j]),
            .c_out(carry_chain0[j+1])
        );

        fa fa1 (
            .a(a[BLOCK_START+j]),
            .b(b_xor[BLOCK_START+j]),
            .c_in(carry_chain1[j]),
            .s(sum1[j]),
            .c_out(carry_chain1[j+1])
        );
      end

      // Store carry outputs from both chains
      assign carry_out0[i] = carry_chain0[BLOCK_SIZE];
      assign carry_out1[i] = carry_chain1[BLOCK_SIZE];

      // Select the correct result based on carry from previous block
      assign sum_comb[BLOCK_START+:BLOCK_SIZE] = block_carry_sel[i] ? sum1 : sum0;
      assign block_carry_sel[i+1] = block_carry_sel[i] ? carry_out1[i] : carry_out0[i];
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
          c_out <= block_carry_sel[NUM_BLOCKS];
        end
      end
    end else begin : combinational
      assign s = sum_comb;
      assign c_out = block_carry_sel[NUM_BLOCKS];
    end
  endgenerate

endmodule
