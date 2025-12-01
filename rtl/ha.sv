module ha (
    input  logic a,
    input  logic b,
    output logic s,
    output logic c_out
);
  assign c_out = a & b;
  assign s     = a ^ b;
endmodule

