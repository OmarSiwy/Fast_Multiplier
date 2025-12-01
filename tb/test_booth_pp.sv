`include "tb/top.h"
// Generic booth partial product testbench
`ifndef TOPNAME
  `define TOPNAME booth_pp  // Default
`endif
`ifndef PIPE
  `define PIPE 0
`endif

/*verilator lint_off DECLFILENAME*/
module top (input clk, input rst);
  parameter W=`W;
  parameter TESTS=`TESTS;
  parameter PIPE=`PIPE;

  logic [W-1:0] y[TESTS];
  logic [2:0] booth_bits[TESTS];
  logic [W:0] pp;
  logic cpl;

  // DUT inputs - registered to control when they change
  logic [W-1:0] dut_y;
  logic [2:0] dut_booth_bits;

  // Expected outputs for verification
  logic [W:0] pp_expected[TESTS];
  logic cpl_expected[TESTS];

  // Test tracking
  logic done;
  integer count;
  integer errors;
  integer tests_run;

  initial begin
    $readmemh({`TESTDIR, "y.hex"}, y);
    $readmemh({`TESTDIR, "booth_bits.hex"}, booth_bits);
    $readmemh({`TESTDIR, "pp.hex"}, pp_expected);
    $readmemh({`TESTDIR, "cpl.hex"}, cpl_expected);
    $display("=====================================");
    $display("Booth PP Testbench");
    $display("  Module: %s", `"TOPNAME`");
    $display("  Width: %0d bits", W);
    $display("  Tests: %0d", TESTS);
    $display("=====================================");
  end

  /* verilator lint_off WIDTHTRUNC */

  // Instantiate DUT with registered inputs
  `TOPNAME #(.W(W), .PIPE(PIPE)) dut(
    .clk(clk), .rst(rst),
    .y(dut_y),
    .booth_bits(dut_booth_bits),
    .pp(pp),
    .cpl(cpl)
  );

  always @(posedge clk) begin
    if(rst) begin
      done <= 0;
      count <= 0;
      errors <= 0;
      tests_run <= 0;
      dut_y <= '0;
      dut_booth_bits <= '0;
    end else begin
      /* verilator lint_off WIDTHEXPAND */

      if(!done) begin
        // Check outputs from current registered inputs
        if(count > PIPE && count <= TESTS + PIPE) begin
          logic pp_match, cpl_match;
          integer check_idx;
          check_idx = count - 1 - PIPE;

          pp_match = (pp == pp_expected[check_idx]);
          cpl_match = (cpl == cpl_expected[check_idx]);

          if (!pp_match || !cpl_match) begin
            errors <= errors + 1;
            $display("ERROR Test %0d: y=%h, booth=%b", check_idx, dut_y, dut_booth_bits);
            $display("  Expected: pp=%h, cpl=%b", pp_expected[check_idx], cpl_expected[check_idx]);
            $display("  Got:      pp=%h, cpl=%b", pp, cpl);
          end else begin
            $display("PASS Test %0d: y=%h, booth=%b → pp=%h, cpl=%b",
                     check_idx, dut_y, dut_booth_bits, pp, cpl);
          end
          tests_run <= tests_run + 1;
        end

        // Apply next test inputs
        if(count < TESTS) begin
          dut_y <= y[count];
          dut_booth_bits <= booth_bits[count];
          count <= count + 1;
        end else if(count == TESTS) begin
          count <= count + 1;
        end else begin
          done <= 1;
        end
      end

      // Print summary when done
      if(done && tests_run > 0) begin
        $display("\n=====================================");
        $display("  GRADE: %0d", (errors == 0) ? 1 : 0);
        if (errors == 0) begin
          $display("=== ALL %0d TESTS PASSED ===", tests_run);
        end else begin
          $display("=== %0d/%0d TESTS FAILED ===", errors, tests_run);
        end
        $display("=====================================");
        tests_run <= 0; // Prevent repeated printing
      end

      /* verilator lint_on WIDTHEXPAND */
    end
  end
  /* verilator lint_on WIDTHTRUNC */
endmodule
/*verilator lint_on DECLFILENAME*/
