module fa (
    input  logic a,
    input  logic b,
    input  logic c_in,
    output logic s,
    output logic c_out
);
  assign s = a ^ b ^ c_in;
  assign c_out = (b & c_in) | (a & (b | c_in));
endmodule
