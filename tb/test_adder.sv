`include "tb/top.h"

/*verilator lint_off DECLFILENAME*/
module top (
    input clk,
    input rst
);
  parameter W = `W;
  parameter M = `M;
  parameter TESTS = `TESTS;
  parameter PIPE = `PIPE;  // Set to 1 if DUT has pipelined/registered outputs, 0 for combinational

  logic [W-1:0] a[TESTS];
  logic [W-1:0] b[TESTS];
  logic c_in[TESTS];
  logic [W-1:0] s;
  logic c_out;

  // DUT inputs - registered to control when they change
  logic [W-1:0] dut_a;
  logic [W-1:0] dut_b;
  logic dut_c_in;

  // Expected results for verification
  logic [W-1:0] expected_s;
  logic expected_c_out;
  logic [W:0] full_sum;

  // Test status tracking
  integer errors;
  integer tests_run;

  logic [W-1:0] expected_s_array[TESTS];
  logic expected_c_out_array[TESTS];

  initial begin
    $readmemh({`TESTDIR, "a.hex"}, a);
    $readmemh({`TESTDIR, "b.hex"}, b);
    $readmemh({`TESTDIR, "c_in.hex"}, c_in);
    // Add these to the initial block where you read other files
    $readmemh({`TESTDIR, "s.hex"}, expected_s_array);
    $readmemh({`TESTDIR, "c_out.hex"}, expected_c_out_array);

    $display("=====================================");
    $display("RCA Testbench Configuration:");
    $display("  Width: %0d bits", W);
    $display("  Tests: %0d", TESTS);
    $display("  Mode: %s", PIPE ? "PIPELINED" : "COMBINATIONAL");
    $display("=====================================");
  end

  logic done;
  logic [$clog2(TESTS+PIPE+1)-1:0] count;

  /* verilator lint_off WIDTHTRUNC */

  // Instantiate DUT with registered inputs
  `TOPNAME #(
      .W(W),
      .PIPE(PIPE),
      .M(M)
  ) dut (
      .clk(clk),
      .rst(rst),
      .a(dut_a),
      .b(dut_b),
      .c_in(dut_c_in),
      .s(s),
      .c_out(c_out)
  );

  always @(posedge clk) begin
    if (rst) begin
      done <= 0;
      count <= 0;
      errors <= 0;
      tests_run <= 0;
      dut_a <= '0;
      dut_b <= '0;
      dut_c_in <= 1'b0;
    end else begin
      /* verilator lint_off WIDTHEXPAND */

      if (!done) begin
        if (count > PIPE && count <= TESTS + PIPE) begin
          integer check_idx;
          logic [W-1:0] a_in, b_in;
          logic c_in_bit;

          check_idx = count - 1 - PIPE;
          a_in = a[check_idx];
          b_in = b[check_idx];
          c_in_bit = c_in[check_idx];

          // Then replace the calculation with
          expected_s = expected_s_array[check_idx];
          expected_c_out = expected_c_out_array[check_idx];
          //full_sum = a_in + b_in + c_in_bit;
          //expected_s = full_sum[W-1:0];
          //expected_c_out = full_sum[W];

          $display("\nTest %0d (%s):", check_idx, PIPE ? "Pipelined" : "Combinational");
          $display("  Inputs:   a=0x%08h, b=0x%08h, c_in=%b", a_in, b_in, c_in_bit);
          $display("  Outputs:  s=0x%08h, c_out=%b", s, c_out);
          $display("  Expected: s=0x%08h, c_out=%b", expected_s, expected_c_out);

          if (s !== expected_s || c_out !== expected_c_out) begin
            $display("  Result: ERROR - Mismatch!");
            errors <= errors + 1;
          end else begin
            $display("  Result: PASS");
          end
          tests_run <= tests_run + 1;
        end

        // Apply next test inputs
        if (count < TESTS) begin
          dut_a <= a[count];
          dut_b <= b[count];
          dut_c_in <= c_in[count];
        end

        if (count <= TESTS + PIPE) begin
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

      /* verilator lint_on WIDTHEXPAND */
    end
  end
  /* verilator lint_on WIDTHTRUNC */
endmodule
/*verilator lint_on DECLFILENAME*/
