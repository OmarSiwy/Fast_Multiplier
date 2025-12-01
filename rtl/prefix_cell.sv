module prefix_cell #(
    parameter PIPE = 0
) (
    input  logic clk,
    input  logic rst,

    input  logic g_hi,
    input  logic p_hi,
    input  logic a_hi,

    input  logic g_lo,
    input  logic p_lo,
    input  logic a_lo,

    output logic g_out,
    output logic p_out,
    output logic a_out
);

  generate
    if (PIPE) begin : pipelined
      logic g_out_comb, p_out_comb, a_out_comb;
      assign g_out_comb = g_hi | (p_hi & g_lo);
      assign p_out_comb = p_hi & p_lo;
      assign a_out_comb = a_hi | (p_hi & a_lo);
      always_ff @(posedge clk) begin
        if (rst) begin
          g_out <= 1'b0;
          p_out <= 1'b0;
          a_out <= 1'b0;
        end else begin
          g_out <= g_out_comb;
          p_out <= p_out_comb;
          a_out <= a_out_comb;
        end
      end
    end else begin : combinational
      assign g_out = g_hi | (p_hi & g_lo);
      assign p_out = p_hi & p_lo;
      assign a_out = a_hi | (p_hi & a_lo);
    end
  endgenerate


endmodule

