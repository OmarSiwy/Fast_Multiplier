module yosys_multiplier #(
    parameter W = 16,
    parameter SIGNED = 1  // 1 = signed, 0 = unsigned
) (
    input  logic [  W-1:0] a,
    input  logic [  W-1:0] b,
    output logic [2*W-1:0] product
);
  generate
    if (SIGNED) begin : gen_signed
      wire signed [W-1:0] a_s = a;
      wire signed [W-1:0] b_s = b;
      assign product = a_s * b_s;
    end else begin : gen_unsigned
      assign product = a * b;
    end
  endgenerate
endmodule
