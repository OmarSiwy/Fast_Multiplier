`include "tb/top.h"
/*verilator lint_off DECLFILENAME*/
module top (
    input clk,
    input rst
);
  parameter W = `W;  // Should match the width used to generate compressor_tree.sv
  parameter TESTS = `TESTS;  // Number of test cases
  parameter BOOTH = `BOOTH;  // 1 for Booth encoding, 0 for binary
  parameter UNSIGNED = `UNSIGNED;  // 1 for unsigned multiplication, 0 for signed
  parameter PROD_W = 2 * W;  // 2*W
  parameter UNSIGNED_BOOTH = (UNSIGNED == 1) & (BOOTH == 1);
  parameter NUM_PP=UNSIGNED_BOOTH ? `NUM_PP+1 : `NUM_PP; // Number of partial products (W for binary, (W+1)/2 for Booth)
  parameter PP_WIDTH = BOOTH ? (W + 1) : W;  // Width of each partial product
  parameter NUM_CPL = `NUM_PP;  // Number of complement bits for Booth encoding
  parameter PIPE = `PIPE;  // 1 to enable pipelining in compressor tree

  int PIPELINE_STAGES;  // <-- runtime variable, not localparam
  generate
    if (BOOTH) begin : gen_booth_compressor
      /* verilator lint_off PINNOTFOUND */
      `TOPNAME #(
          .PIPE(PIPE)
      ) dut (
          .clk(clk),
          .rst(rst),
          .pp(pp_packed),
          .cpl(cpl_packed),
          .sum(sum),
          .carry(carry)
      );
      /* verilator lint_on PINNOTFOUND */

      // Capture parameter at time 0
      initial PIPELINE_STAGES = PIPE ? dut.COMPRESSOR_TREE_STAGES : 0;

    end else begin : gen_binary_compressor
      /* verilator lint_off PINMISSING */
      `TOPNAME #(
          .PIPE(PIPE)
      ) dut (
          .clk(clk),
          .rst(rst),
          .pp(pp_packed),
          .sum(sum),
          .carry(carry)
      );
      /* verilator lint_on PINMISSING */

      // Capture parameter at time 0
      initial PIPELINE_STAGES = PIPE ? dut.COMPRESSOR_TREE_STAGES : 0;
    end
    logic [W-1:0] a[TESTS];
    logic [W-1:0] b[TESTS];
    logic [PROD_W-1:0] expected[TESTS];

    logic [W-1:0] a_in;
    logic [W-1:0] b_in;
    logic [PROD_W-1:0] expected_in;

    // Storage for all partial products - flattened structure
    // pp_mem[pp_index * TESTS + test_index]
    logic [PP_WIDTH-1:0] pp_mem[NUM_PP * TESTS];
    logic cpl_mem[NUM_CPL * TESTS];

    // Current partial products for DUT
    logic [NUM_PP-1:0][PP_WIDTH-1:0] pp_packed;
    logic [PROD_W-1:0] sum;
    logic [PROD_W-1:0] carry;
    logic [PROD_W-1:0] product;

    // For Booth encoding
    /* verilator lint_off ASCRANGE */
    logic [0:NUM_CPL-1] cpl_packed;
    /* verilator lint_on ASCRANGE */

    initial begin
      // Load test vectors
      $readmemh({`TESTDIR, "test_a.hex"}, a);
      $readmemh({`TESTDIR, "test_b.hex"}, b);
      $readmemh({`TESTDIR, "test_expected.hex"}, expected);

      // Load all partial products using readmemh
      for (int i = 0; i < NUM_PP; i++) begin
        $readmemh($sformatf("%stest_pp%0d.hex", `TESTDIR, i), pp_mem, i * TESTS,
                  (i + 1) * TESTS - 1);
      end

      // Load complement bits if using Booth
      if (BOOTH) begin
        for (int i = 0; i < NUM_PP; i++) begin
          $readmemh($sformatf("%stest_cpl%0d.hex", `TESTDIR, i), cpl_mem, i * TESTS,
                    (i + 1) * TESTS - 1);
        end
      end

    end

    logic done;
    logic [$clog2(TESTS+128):0] count;  // Auto-size based on TESTS + max pipeline stages

  endgenerate
  // Select partial products for current test
  always_comb begin
    for (int i = 0; i < NUM_PP; i++) begin
      /* verilator lint_off WIDTHEXPAND */
      /* verilator lint_off WIDTHTRUNC */
      pp_packed[i] = pp_mem[i*TESTS+count];
      a_in = a[i*(TESTS-PIPELINE_STAGES)+count];
      b_in = b[i*(TESTS-PIPELINE_STAGES)+count];
      expected_in = expected[i*(TESTS-PIPELINE_STAGES)+count];
      /* verilator lint_on WIDTHEXPAND */
      /* verilator lint_on WIDTHTRUNC */
      if (BOOTH) begin
        /* verilator lint_off WIDTHEXPAND */
        cpl_packed[i] = cpl_mem[i*TESTS+count];
        /* verilator lint_on WIDTHEXPAND */
      end else begin
        cpl_packed[i] = 1'b0;
      end
    end
  end
  // Final adder: product = sum + (carry << 1)
  assign product = sum + (carry);

  integer errors = 0;
  integer tests_run = 0;

  always @(posedge clk) begin
    if (rst) begin
      count <= 0;
      done <= 0;
      errors <= 0;
      tests_run <= 0;
      /* verilator lint_off WIDTHEXPAND */
    end else if (count >= PIPELINE_STAGES && count < TESTS + PIPELINE_STAGES) begin
      /* verilator lint_off WIDTHTRUNC */
      $display("Test %0d: a=%h, b=%h", count - PIPELINE_STAGES, a[count-PIPELINE_STAGES],
               b[count-PIPELINE_STAGES]);
      if (!UNSIGNED) begin
        $display("  Signed a = %0d, b = %0d", $signed(a[count-PIPELINE_STAGES]),
                 $signed(b[count-PIPELINE_STAGES]));
      end else begin
        $display("  Unsigned a = %0d, b = %0d", a[count-PIPELINE_STAGES], b[count-PIPELINE_STAGES]);
      end
      $display("  Product    = %h", product);
      $display("  Expected   = %h", expected[count-PIPELINE_STAGES]);
      $display("  Sum        = %h", sum);
      $display("  Carry      = %h", carry);

      tests_run <= tests_run + 1;

      if (product == expected[count-PIPELINE_STAGES]) begin
        $display("  ✓ PASS");
      end else begin
        $display("  ✗ FAIL");
        errors <= errors + 1;

        $display("  Partial Products:");
        for (int i = 0; i < NUM_PP; i++) begin
          if (BOOTH) begin
            if ((i == NUM_PP - 1) && UNSIGNED) begin
              // Skip the last cpl bit for unsigned multiplication
              $display("    PP[%0d] = %h", i, pp_packed[i]);
              continue;
            end
            $display("    PP[%0d] = %h  cpl=%b", i, pp_packed[i], cpl_packed[i]);
          end else begin
            $display("    PP[%0d] = %h", i, pp_packed[i]);
          end
        end
      end
      $display("");
      /* verilator lint_on WIDTHTRUNC */

    end else if (!done & (count >= PIPELINE_STAGES)) begin
      /* verilator lint_on WIDTHEXPAND */
      done <= 1;

      $display("\n=====================================");
      $display("TEST SUMMARY:");
      $display("  Total tests run: %0d", tests_run);
      $display("  Passed: %0d", tests_run - errors);
      $display("  Failed: %0d", errors);
      $display("  GRADE: %0d", (errors == 0) ? 1 : 0);
      $display("=====================================\n");

      $finish;
    end
    count <= count + 1;
  end

endmodule
/*verilator lint_on DECLFILENAME*/
