`include "tb/top.h"
/*verilator lint_off DECLFILENAME*/
module top (
    input clk,
    input rst
);
  parameter W = `W;
  parameter TESTS = `TESTS;
  parameter M = `M;
  parameter PIPE = `PIPE;
  parameter PROD_W = 2 * W;

  // Test vectors
  logic [W-1:0] a_vals[TESTS];
  logic [W-1:0] b_vals[TESTS];
  logic [PROD_W-1:0] expected[TESTS];

  // DUT signals
  logic [W-1:0] dut_a;
  logic [W-1:0] dut_b;
  logic [PROD_W-1:0] product;

  // Load test data
  initial begin
    $readmemh({`TESTDIR, "a_vals.hex"}, a_vals);
    $readmemh({`TESTDIR, "b_vals.hex"}, b_vals);
    $readmemh({`TESTDIR, "p_vals.hex"}, expected);

    $display("=====================================");
    $display("Multiplier Testbench Configuration:");
    $display("  Width: %0d bits", W);
    $display("  Tests: %0d", TESTS);
    $display("  Pipeline Stages (M): %0d", M);
    $display("  Pipelining Level (PIPE): %0d", PIPE);
    $display("  Encoding: %s", `ENCODING);
    $display("=====================================");
  end

  // Instantiate multiplier DUT
  `TOPNAME #(
      .W(W),
      .PIPE(PIPE),
      .M(M)
  ) dut (
      .clk(clk),
      .rst(rst),
      .a(dut_a),
      .b(dut_b),
      .product(product)
  );

  // Test control
  logic   done;
  integer count;
  integer errors;
  integer tests_run;
  integer pipeline_delay;

  // Calculate pipeline delay based on M and PIPE
  initial begin
    pipeline_delay = 0;
    if (M > 0) pipeline_delay = pipeline_delay + 1;  // PP register stage
    if (PIPE > 0) begin
      // Add compressor tree stages (depends on algorithm but typically 3-5)
      // For simplicity, we'll use a conservative estimate
      pipeline_delay = pipeline_delay + 5;
    end
    if (M > 1) pipeline_delay = pipeline_delay + 1;  // Output register stage

    $display("Calculated pipeline delay: %0d cycles", pipeline_delay);
  end

  always @(posedge clk) begin
    if (rst) begin
      done <= 0;
      count <= 0;
      errors <= 0;
      tests_run <= 0;
      dut_a <= '0;
      dut_b <= '0;
    end else begin
      if (!done) begin
        // Check results after pipeline delay
        if (count > pipeline_delay && count <= TESTS + pipeline_delay) begin
          integer check_idx;
          logic [W-1:0] a_in, b_in;
          logic [PROD_W-1:0] expected_product;

          check_idx = count - 1 - pipeline_delay;
          a_in = a_vals[check_idx];
          b_in = b_vals[check_idx];
          expected_product = expected[check_idx];

          $display("\nTest %0d:", check_idx);
          $display("  Inputs:   a=0x%0h (%0d), b=0x%0h (%0d)", a_in, a_in, b_in, b_in);
          $display("  Output:   product=0x%0h (%0d)", product, product);
          $display("  Expected: product=0x%0h (%0d)", expected_product, expected_product);

          if (product !== expected_product) begin
            $display("  Result: ERROR - Mismatch!");
            $display("  Difference: 0x%0h", product ^ expected_product);
            errors <= errors + 1;
          end else begin
            $display("  Result: PASS");
          end
          tests_run <= tests_run + 1;
        end

        // Apply next test inputs
        if (count < TESTS) begin
          dut_a <= a_vals[count];
          dut_b <= b_vals[count];
        end

        if (count <= TESTS + pipeline_delay) begin
          count <= count + 1;
        end else begin
          done <= 1;
        end
      end

      // Print summary when done
      if (done && tests_run > 0) begin
        $display("\n=====================================");
        $display("TEST SUMMARY:");
        $display("  Total tests run: %0d", tests_run);
        $display("  Passed: %0d", tests_run - errors);
        $display("  Failed: %0d", errors);
        $display("  GRADE: %0d", (errors == 0) ? 1 : 0);
        if (errors == 0) begin
          $display("  Result: ALL TESTS PASSED!");
        end else begin
          $display("  Result: %0d FAILURES DETECTED!", errors);
        end
        $display("=====================================");
        tests_run <= 0;  // Prevent repeated printing
      end
    end
  end

endmodule
/*verilator lint_on DECLFILENAME*/
