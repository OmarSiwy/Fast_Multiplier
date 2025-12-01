module booth_pp #(
    parameter W    = 16,
    parameter PIPE = 0
) (
    // Only if PIPE=1
    input logic clk,
    input logic rst,

    input  logic [W-1:0] y,           // Multiplicand
    input  logic [  2:0] booth_bits,  // Booth Encoded Input
    output logic [  W:0] pp,          // Partial Product Output
    output logic         cpl          // Complement Bit because its 2s complement
);
  logic       one;  // Multiply by ±1
  logic       two;  // Multiply by ±2
  logic       sign;  // Sign bit (negate if 1)

  logic [W:0] y_ext;  // Sign-extended Y
  logic [W:0] y_shifted;  // Y << 1 (for 2Y)
  logic [W:0] selected;  // Mux output
  logic [W:0] pp_comb;  // Combinational partial product
  logic       cpl_comb;  // Combinational complement bit

  // Booth decoding logic
  // Decode booth_bits to determine operation
  // 000, 111 → ×0
  // 001, 010 → ×(+1)
  // 011      → ×(+2)
  // 100      → ×(-2)
  // 101, 110 → ×(-1)
  always_comb begin
    one  = (booth_bits == 3'b001) || (booth_bits == 3'b010) ||
               (booth_bits == 3'b101) || (booth_bits == 3'b110);
    two = (booth_bits == 3'b011) || (booth_bits == 3'b100);
    sign = booth_bits[2];
  end

  // Partial product generation
  always_comb begin
    y_ext = {{1{y[W-1]}}, y};
    y_shifted = {y_ext[W-1:0], 1'b0};

    // Multiplexer: select 0, 1Y, or 2Y
    if (two) selected = y_shifted;
    else if (one) selected = y_ext;
    else selected = {(W + 1) {1'b0}};

    cpl_comb = sign;

    // Conditional negation (one's complement)
    // If sign bit is set, invert all bits
    if (sign) begin
      pp_comb = ~selected;
    end else begin  // for the latch instead of ff
      pp_comb = selected;
    end
  end

  // Optional pipeline stage
  generate
    if (PIPE == 1) begin : gen_pipe
      always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
          pp  <= {(W + 1) {1'b0}};
          cpl <= 1'b0;
        end else begin
          pp  <= pp_comb;
          cpl <= cpl_comb;
        end
      end
    end else begin : gen_comb
      assign pp  = pp_comb;
      assign cpl = cpl_comb;
    end
  endgenerate

endmodule
