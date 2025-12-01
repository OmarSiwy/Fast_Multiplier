module gpk #(
    parameter bit PIPE = 0
) (
    input  logic clk,
    input  logic rst,
    input  logic a,
    input  logic b,
    output logic g,
    output logic p,
    output logic k
);

  generate
    if (PIPE) begin : pipelined
      always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
          g <= 1'b0;
          p <= 1'b0;
          k <= 1'b0;
        end else begin
          g <= a & b;
          p <= a ^ b;
          k <= ~a & ~b;
        end
      end
    end else begin : combinational
      assign g = a & b;
      assign p = a ^ b;
      assign k = ~a & ~b;
    end
  endgenerate

endmodule
