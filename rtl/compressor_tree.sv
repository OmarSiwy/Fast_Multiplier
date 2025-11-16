//
// Bickerstaff Tree Compressor
// Algorithm: BICKERSTAFF
// Input Width: 4 bits
// Encoding: BINARY
// Type: Unsigned
// Partial Products: 4
// Product Width: 8
// Reduction Stages: 2
//

module compressor_tree #(
    parameter PIPE = 0
)(
    input logic clk,
    input logic rst,
    input logic [3:0][3:0] pp,
    output logic [7:0] sum,
    output logic [7:0] carry
);

    parameter COMPRESSOR_TREE_STAGES = 0;

    // FA and HA output wires
    logic fa_s0_c2_n0_s, fa_s0_c2_n0_c;
    logic fa_s0_c3_n1_s, fa_s0_c3_n1_c;
    logic fa_s0_c4_n2_s, fa_s0_c4_n2_c;
    logic fa_s1_c3_n0_s, fa_s1_c3_n0_c;
    logic fa_s1_c5_n1_s, fa_s1_c5_n1_c;
    logic ha_s0_c1_n0_s, ha_s0_c1_n0_c;
    logic ha_s1_c2_n0_s, ha_s1_c2_n0_c;
    logic ha_s1_c4_n1_s, ha_s1_c4_n1_c;

    // Stage 0 signals
    logic [0:0] stage0_col0;
    logic [1:0] stage0_col1;
    logic [2:0] stage0_col2;
    logic [3:0] stage0_col3;
    logic [2:0] stage0_col4;
    logic [1:0] stage0_col5;
    logic [0:0] stage0_col6;

    // Stage 1 signals
    logic [0:0] stage1_col0;
    logic [0:0] stage1_col1;
    logic [1:0] stage1_col2;
    logic [2:0] stage1_col3;
    logic [1:0] stage1_col4;
    logic [2:0] stage1_col5;
    logic [0:0] stage1_col6;

    // Stage 2 signals
    logic [0:0] stage2_col0;
    logic [0:0] stage2_col1;
    logic [0:0] stage2_col2;
    logic [1:0] stage2_col3;
    logic [1:0] stage2_col4;
    logic [1:0] stage2_col5;
    logic [1:0] stage2_col6;

    // Stage 0: Partial Product Assignment
    assign stage0_col0[0] = pp[0][0];
    assign stage0_col1[0] = pp[0][1];
    assign stage0_col1[1] = pp[1][0];
    assign stage0_col2[0] = pp[0][2];
    assign stage0_col2[1] = pp[1][1];
    assign stage0_col2[2] = pp[2][0];
    assign stage0_col3[0] = pp[0][3];
    assign stage0_col3[1] = pp[1][2];
    assign stage0_col3[2] = pp[2][1];
    assign stage0_col3[3] = pp[3][0];
    assign stage0_col4[0] = pp[1][3];
    assign stage0_col4[1] = pp[2][2];
    assign stage0_col4[2] = pp[3][1];
    assign stage0_col5[0] = pp[2][3];
    assign stage0_col5[1] = pp[3][2];
    assign stage0_col6[0] = pp[3][3];

    // Stage 1: Reduction
    fa fa_s0_c2_n0 (
        .a(stage0_col2[0]),
        .b(stage0_col2[1]),
        .c_in(stage0_col2[2]),
        .s(fa_s0_c2_n0_s),
        .c_out(fa_s0_c2_n0_c)
    );

    fa fa_s0_c3_n1 (
        .a(stage0_col3[0]),
        .b(stage0_col3[1]),
        .c_in(stage0_col3[2]),
        .s(fa_s0_c3_n1_s),
        .c_out(fa_s0_c3_n1_c)
    );

    fa fa_s0_c4_n2 (
        .a(stage0_col4[0]),
        .b(stage0_col4[1]),
        .c_in(stage0_col4[2]),
        .s(fa_s0_c4_n2_s),
        .c_out(fa_s0_c4_n2_c)
    );

    ha ha_s0_c1_n0 (
        .a(stage0_col1[0]),
        .b(stage0_col1[1]),
        .s(ha_s0_c1_n0_s),
        .c_out(ha_s0_c1_n0_c)
    );

    // Map to Stage 1 columns
    assign stage1_col0[0] = stage0_col0[0];
    assign stage1_col1[0] = ha_s0_c1_n0_s;
    assign stage1_col2[0] = ha_s0_c1_n0_c;
    assign stage1_col2[1] = fa_s0_c2_n0_s;
    assign stage1_col3[0] = fa_s0_c2_n0_c;
    assign stage1_col3[1] = fa_s0_c3_n1_s;
    assign stage1_col3[2] = stage0_col3[3];
    assign stage1_col4[0] = fa_s0_c3_n1_c;
    assign stage1_col4[1] = fa_s0_c4_n2_s;
    assign stage1_col5[0] = fa_s0_c4_n2_c;
    assign stage1_col5[1] = stage0_col5[0];
    assign stage1_col5[2] = stage0_col5[1];
    assign stage1_col6[0] = stage0_col6[0];

    // Stage 2: Reduction
    fa fa_s1_c3_n0 (
        .a(stage1_col3[0]),
        .b(stage1_col3[1]),
        .c_in(stage1_col3[2]),
        .s(fa_s1_c3_n0_s),
        .c_out(fa_s1_c3_n0_c)
    );

    fa fa_s1_c5_n1 (
        .a(stage1_col5[0]),
        .b(stage1_col5[1]),
        .c_in(stage1_col5[2]),
        .s(fa_s1_c5_n1_s),
        .c_out(fa_s1_c5_n1_c)
    );

    ha ha_s1_c2_n0 (
        .a(stage1_col2[0]),
        .b(stage1_col2[1]),
        .s(ha_s1_c2_n0_s),
        .c_out(ha_s1_c2_n0_c)
    );

    ha ha_s1_c4_n1 (
        .a(stage1_col4[0]),
        .b(stage1_col4[1]),
        .s(ha_s1_c4_n1_s),
        .c_out(ha_s1_c4_n1_c)
    );

    // Map to Stage 2 columns
    assign stage2_col0[0] = stage1_col0[0];
    assign stage2_col1[0] = stage1_col1[0];
    assign stage2_col2[0] = ha_s1_c2_n0_s;
    assign stage2_col3[0] = ha_s1_c2_n0_c;
    assign stage2_col3[1] = fa_s1_c3_n0_s;
    assign stage2_col4[0] = fa_s1_c3_n0_c;
    assign stage2_col4[1] = ha_s1_c4_n1_s;
    assign stage2_col5[0] = ha_s1_c4_n1_c;
    assign stage2_col5[1] = fa_s1_c5_n1_s;
    assign stage2_col6[0] = fa_s1_c5_n1_c;
    assign stage2_col6[1] = stage1_col6[0];

    // Final outputs (sum and carry)
    assign sum[0] = stage2_col0[0];
    assign carry[0] = 1'b0;
    assign sum[1] = stage2_col1[0];
    assign carry[1] = 1'b0;
    assign sum[2] = stage2_col2[0];
    assign carry[2] = 1'b0;
    assign sum[3] = stage2_col3[0];
    assign carry[3] = stage2_col3[1];
    assign sum[4] = stage2_col4[0];
    assign carry[4] = stage2_col4[1];
    assign sum[5] = stage2_col5[0];
    assign carry[5] = stage2_col5[1];
    assign sum[6] = stage2_col6[0];
    assign carry[6] = stage2_col6[1];
    assign sum[7] = 1'b0;
    assign carry[7] = 1'b0;

endmodule