`include "tb/top.h"

/*verilator lint_off DECLFILENAME*/
module top (
    input clk,
    input rst
);
  parameter TESTS = `TESTS;
  parameter PIPE = `PIPE;  // Set to 1 if DUT is pipelined, 0 if combinational

  // Test input memories
  logic a_in [TESTS];
  logic b_in [TESTS];

  // Expected outputs
  logic g_exp[TESTS];
  logic p_exp[TESTS];
  logic k_exp[TESTS];

  // DUT inputs (registered)
  logic dut_a, dut_b;

  // DUT outputs
  logic g_out;
  logic p_out;
  logic k_out;

  // Test tracking
  integer errors;
  integer tests_run;
  logic done;
  logic [9:0] count;  // enough for many tests

  // Instantiate DUT
  `TOPNAME #(
      .PIPE(PIPE)
  ) dut (
      .clk(clk),
      .rst(rst),
      .a  (dut_a),
      .b  (dut_b),
      .g  (g_out),
      .p  (p_out),
      .k  (k_out)
  );

  initial begin
    // Load test data
    $readmemh({`TESTDIR, "a.hex"}, a_in);
    $readmemh({`TESTDIR, "b.hex"}, b_in);
    $readmemh({`TESTDIR, "g.hex"}, g_exp);
    $readmemh({`TESTDIR, "p.hex"}, p_exp);
    $readmemh({`TESTDIR, "k.hex"}, k_exp);

    $display("=====================================");
    $display("GPK Testbench Configuration:");
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
      dut_a <= 0;
      dut_b <= 0;
    end else begin
      if (!done) begin
        // Check expected vs actual, accounting for PIPE latency
        if (count > PIPE && count <= TESTS + PIPE) begin
          integer idx;
          idx = integer'(count) - 1 - PIPE;

          $display("\nTest %0d (%s):", idx, PIPE ? "Pipelined" : "Combinational");
          $display("  Inputs : a=%0b b=%0b", a_in[idx], b_in[idx]);
          $display("  Outputs: g=%0b p=%0b k=%0b", g_out, p_out, k_out);
          $display("  Expect : g=%0b p=%0b k=%0b", g_exp[idx], p_exp[idx], k_exp[idx]);

          if (g_out !== g_exp[idx] || p_out !== p_exp[idx] || k_out !== k_exp[idx]) begin
            $display("  Result: ERROR - mismatch!");
            errors <= errors + 1;
          end else begin
            $display("  Result: PASS");
          end

          tests_run <= tests_run + 1;
        end

        // Apply next test vector
        if (count < TESTS) begin
          dut_a <= a_in[count];
          dut_b <= b_in[count];
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

