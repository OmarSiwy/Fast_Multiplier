module cla #(
    parameter int W = 8,
    parameter int M = 4,  // Block/chunk size for CLA
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
  // Ceiling division (source: chatgpt ngl)
  localparam int NUM_BLOCKS = (W + M - 1) / M;

  // Generate and propagate signals for each bit
  logic [W-1:0] g, p;
  logic [W-1:0] sum_comb;
  logic [NUM_BLOCKS:0] block_carry_out;
  logic [W-1:0] b_xor;  // XOR b with c_in for subtraction

  // When c_in=1, this implements subtraction: a + ~b + 1
  // When c_in=0, this implements addition: a + b + 0
  assign b_xor = b ^ {W{c_in}};

  // Generate G and P for each bit position
  genvar i, j;
  generate
    for (i = 0; i < W; i++) begin : gpk_gen
      assign g[i] = a[i] & b_xor[i];  // Generate
      assign p[i] = a[i] ^ b_xor[i];  // Propagate
    end
  endgenerate

  assign block_carry_out[0] = c_in;

  // CLA blocks
  generate
    for (i = 0; i < NUM_BLOCKS; i++) begin : cla_blocks
      localparam int BLOCK_START = i * M;
      localparam int BLOCK_END = (i * M + M) > W ? W : (i * M + M);
      localparam int BLOCK_SIZE = BLOCK_END - BLOCK_START;

      logic [BLOCK_SIZE-1:0] local_g, local_p;
      logic [BLOCK_SIZE:0] local_c;

      for (j = 0; j < BLOCK_SIZE; j++) begin : extract_gp
        assign local_g[j] = g[BLOCK_START+j];
        assign local_p[j] = p[BLOCK_START+j];
      end

      // Carry input to this block comes from previous block's output
      assign local_c[0] = block_carry_out[i];

      // Carry lookahead logic
      for (j = 0; j < BLOCK_SIZE; j++) begin : lookahead
        if (j == 0) begin : bit0
          assign local_c[1] = local_g[0] | (local_p[0] & local_c[0]);
        end else if (j == 1 && BLOCK_SIZE > 1) begin : bit1
          assign local_c[2] = local_g[1] | 
                                       (local_p[1] & local_g[0]) | 
                                       (local_p[1] & local_p[0] & local_c[0]);
        end else if (j == 2 && BLOCK_SIZE > 2) begin : bit2
          assign local_c[3] = local_g[2] | 
                                       (local_p[2] & local_g[1]) | 
                                       (local_p[2] & local_p[1] & local_g[0]) | 
                                       (local_p[2] & local_p[1] & local_p[0] & local_c[0]);
        end else if (j == 3 && BLOCK_SIZE > 3) begin : bit3
          assign local_c[4] = local_g[3] | 
                                       (local_p[3] & local_g[2]) | 
                                       (local_p[3] & local_p[2] & local_g[1]) | 
                                       (local_p[3] & local_p[2] & local_p[1] & local_g[0]) | 
                                       (local_p[3] & local_p[2] & local_p[1] & local_p[0] & local_c[0]);
        end else if (j > 3) begin : bit_n
          assign local_c[j+1] = local_g[j] | (local_p[j] & local_c[j]);
        end
      end

      for (j = 0; j < BLOCK_SIZE; j++) begin : sum_gen
        assign sum_comb[BLOCK_START+j] = local_p[j] ^ local_c[j];
      end

      // Carry output to next block
      assign block_carry_out[i+1] = local_c[BLOCK_SIZE];
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
          c_out <= block_carry_out[NUM_BLOCKS];
        end
      end
    end else begin : combinational
      assign s = sum_comb;
      assign c_out = block_carry_out[NUM_BLOCKS];
    end
  endgenerate

endmodule
