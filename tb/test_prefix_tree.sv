`include "tb/top.h"

/*verilator lint_off DECLFILENAME*/
module top (
    input clk,
    input rst
);
  parameter TESTS = `TESTS;
  parameter PIPE = `PIPE;  // Set to 1 if DUT is pipelined, 0 if combinational

  // Test input memories
  logic g_hi [TESTS];
  logic p_hi [TESTS];
  logic a_hi [TESTS];
  logic g_lo [TESTS];
  logic p_lo [TESTS];
  logic a_lo [TESTS];

  // Expected outputs
  logic g_exp[TESTS];
  logic p_exp[TESTS];
  logic a_exp[TESTS];

  // DUT inputs (registered)
  logic dut_g_hi, dut_p_hi, dut_a_hi;
  logic dut_g_lo, dut_p_lo, dut_a_lo;

  // DUT outputs
  logic   g_out;
  logic   p_out;
  logic   a_out;

  // Test tracking
  integer errors;
  integer tests_run;
  logic   done;
  integer count;  // enough for many tests

  // Instantiate DUT
  `TOPNAME #(
      .PIPE(PIPE)
  ) dut (
      .clk  (clk),
      .rst  (rst),
      .g_hi (dut_g_hi),
      .p_hi (dut_p_hi),
      .a_hi (dut_a_hi),
      .g_lo (dut_g_lo),
      .p_lo (dut_p_lo),
      .a_lo (dut_a_lo),
      .g_out(g_out),
      .p_out(p_out),
      .a_out(a_out)
  );

  initial begin
    // Load test data
    $readmemh({`TESTDIR, "g_hi.hex"}, g_hi);
    $readmemh({`TESTDIR, "p_hi.hex"}, p_hi);
    $readmemh({`TESTDIR, "a_hi.hex"}, a_hi);

    $readmemh({`TESTDIR, "g_lo.hex"}, g_lo);
    $readmemh({`TESTDIR, "p_lo.hex"}, p_lo);
    $readmemh({`TESTDIR, "a_lo.hex"}, a_lo);

    $readmemh({`TESTDIR, "g_out.hex"}, g_exp);
    $readmemh({`TESTDIR, "p_out.hex"}, p_exp);
    $readmemh({`TESTDIR, "a_out.hex"}, a_exp);

    $display("=====================================");
    $display("Prefix Cell Testbench Configuration:");
    $display("  Tests: %0d", TESTS);
    $display("  Mode: %s", PIPE ? "PIPELINED" : "COMBINATIONAL");
    $display("=====================================");
  end

  /* verilator lint_off WIDTHTRUNC */
  always @(posedge clk) begin
    if (rst) begin
      done <= 0;
      count <= 0;
      errors <= 0;
      tests_run <= 0;
      dut_g_hi <= 0;
      dut_p_hi <= 0;
      dut_a_hi <= 0;
      dut_g_lo <= 0;
      dut_p_lo <= 0;
      dut_a_lo <= 0;
    end else begin
      if (!done) begin
        // Check expected vs actual, accounting for PIPE latency
        if (count > PIPE && count <= TESTS + PIPE) begin
          integer idx;
          idx = integer'(count) - 1 - PIPE;

          $display("\nTest %0d (%s):", idx, PIPE ? "Pipelined" : "Combinational");
          $display("  Inputs : g_hi=%0b p_hi=%0b a_hi=%0b | g_lo=%0b p_lo=%0b a_lo=%0b", g_hi[idx],
                   p_hi[idx], a_hi[idx], g_lo[idx], p_lo[idx], a_lo[idx]);
          $display("  Outputs: g_out=%0b p_out=%0b a_out=%0b", g_out, p_out, a_out);
          $display("  Expect : g_out=%0b p_out=%0b a_out=%0b", g_exp[idx], p_exp[idx], a_exp[idx]);

          if (g_out !== g_exp[idx] || p_out !== p_exp[idx] || a_out !== a_exp[idx]) begin
            $display("  Result: ERROR - mismatch!");
            errors <= errors + 1;
          end else begin
            $display("  Result: PASS");
          end

          tests_run <= tests_run + 1;
        end

        // Apply next test vector
        if (count < TESTS) begin
          dut_g_hi <= g_hi[count];
          dut_p_hi <= p_hi[count];
          dut_a_hi <= a_hi[count];
          dut_g_lo <= g_lo[count];
          dut_p_lo <= p_lo[count];
          dut_a_lo <= a_lo[count];
        end

        if (count <= TESTS + PIPE) count <= count + 1;
        else done <= 1;
      end

      // Summary
      if (done && tests_run > 0) begin
        $display("\n=====================================");
        $display("TEST SUMMARY:");
        $display("  Total tests run: %0d", tests_run);
        $display("  Passed: %0d", tests_run - errors);
        $display("  Failed: %0d", errors);
        $display("  GRADE: %0d", (errors == 0) ? 1 : 0);
        if (errors == 0) $display("  Result: ALL TESTS PASSED!");
        else $display("  Result: %0d FAILURES DETECTED!", errors);
        $display("=====================================");
        tests_run <= 0;  // stop repeated summary
      end
    end
  end
  /* verilator lint_on WIDTHTRUNC */

endmodule
/*verilator lint_on DECLFILENAME*/

