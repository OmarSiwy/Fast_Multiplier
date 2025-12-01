`include "tb/top.h"

/*verilator lint_off DECLFILENAME*/
module top (
    input clk,
    input rst
);
  parameter TESTS = `TESTS;
  parameter WIDTH = `W;
  parameter PIPE = `PIPE;
  parameter TECHNIQUE = `TECHNIQUE;  // 0=kogge-stone, 1=sklansky, 2=brent-kung

  // Test input memories
  logic [WIDTH-1:0] g_in [TESTS];
  logic [WIDTH-1:0] p_in [TESTS];
  logic [WIDTH-1:0] a_in [TESTS];

  // Expected outputs
  logic [WIDTH-1:0] g_exp[TESTS];
  logic [WIDTH-1:0] p_exp[TESTS];
  logic [WIDTH-1:0] a_exp[TESTS];

  // DUT inputs
  logic [WIDTH-1:0] dut_g_in;
  logic [WIDTH-1:0] dut_p_in;
  logic [WIDTH-1:0] dut_a_in;

  // DUT outputs
  logic [WIDTH-1:0] g_out;
  logic [WIDTH-1:0] p_out;
  logic [WIDTH-1:0] a_out;

  // Test tracking
  integer errors;
  integer tests_run;
  logic   done;
  integer count;

  // Calculate latency based on pipeline depth and technique
  integer latency;
  integer num_levels;

  initial begin
    // Calculate number of levels based on technique
    if (TECHNIQUE == 2) begin  // Brent-Kung
      num_levels = 2 * $clog2(WIDTH) - 1;
    end else begin  // Kogge-Stone or Sklansky
      num_levels = $clog2(WIDTH);
    end

    // Latency calculation
    if (PIPE) begin
      // All techniques have latency equal to number of levels
      latency = num_levels;
    end else begin
      latency = 0;  // Combinational
    end
  end

  // Instantiate DUT
  `TOPNAME #(
      .WIDTH(WIDTH),
      .PIPE (PIPE)
  ) dut (
      .clk  (clk),
      .rst  (rst),
      .g_in (dut_g_in),
      .p_in (dut_p_in),
      .a_in (dut_a_in),
      .g_out(g_out),
      .p_out(p_out),
      .a_out(a_out)
  );

  initial begin
    // Load test data
    $readmemh({`TESTDIR, "g_in.hex"}, g_in);
    $readmemh({`TESTDIR, "p_in.hex"}, p_in);
    $readmemh({`TESTDIR, "a_in.hex"}, a_in);

    $readmemh({`TESTDIR, "g_out.hex"}, g_exp);
    $readmemh({`TESTDIR, "p_out.hex"}, p_exp);
    $readmemh({`TESTDIR, "a_out.hex"}, a_exp);

    $display("=====================================");
    $display("Prefix Tree Testbench Configuration:");
    $display("  Tests: %0d", TESTS);
    $display("  Width: %0d bits", WIDTH);
    $display("  Technique: %s", TECHNIQUE == 0 ? "Kogge-Stone" : (TECHNIQUE == 1 ? "Sklansky" : "Brent-Kung"));
    $display("  Mode: %s", PIPE ? "PIPELINED" : "COMBINATIONAL");
    $display("  Levels: %0d", num_levels);
    $display("  Latency: %0d cycles", latency);
    $display("=====================================");
  end

  /* verilator lint_off WIDTHTRUNC */

  always @(posedge clk) begin
    if (rst) begin
      done <= 0;
      count <= 0;
      errors <= 0;
      tests_run <= 0;
      dut_g_in <= '0;
      dut_p_in <= '0;
      dut_a_in <= '0;
    end else begin
      if (!done) begin
        // Check results after pipeline delay
        if (count > latency && count <= TESTS + latency) begin
          integer check_idx;
          logic [WIDTH-1:0] g_in_val, p_in_val, a_in_val;
          logic [WIDTH-1:0] g_exp_val, p_exp_val, a_exp_val;

          check_idx = count - 1 - latency;
          g_in_val = g_in[check_idx];
          p_in_val = p_in[check_idx];
          a_in_val = a_in[check_idx];
          g_exp_val = g_exp[check_idx];
          p_exp_val = p_exp[check_idx];
          a_exp_val = a_exp[check_idx];

          $display("\nTest %0d (%s):", check_idx, PIPE ? "Pipelined" : "Combinational");
          $display("  g_in  = 0x%0h", g_in_val);
          $display("  p_in  = 0x%0h", p_in_val);
          $display("  a_in  = 0x%0h", a_in_val);
          $display("  g_out = 0x%0h (expected: 0x%0h)", g_out, g_exp_val);
          $display("  p_out = 0x%0h (expected: 0x%0h)", p_out, p_exp_val);
          $display("  a_out = 0x%0h (expected: 0x%0h)", a_out, a_exp_val);

          if (g_out !== g_exp_val || p_out !== p_exp_val || a_out !== a_exp_val) begin
            $display("  Result: ERROR - mismatch!");
            if (g_out !== g_exp_val) $display("    g_out mismatch: got 0x%0h, expected 0x%0h", g_out, g_exp_val);
            if (p_out !== p_exp_val) $display("    p_out mismatch: got 0x%0h, expected 0x%0h", p_out, p_exp_val);
            if (a_out !== a_exp_val) $display("    a_out mismatch: got 0x%0h, expected 0x%0h", a_out, a_exp_val);
            errors <= errors + 1;
          end else begin
            $display("  Result: PASS");
          end
          tests_run <= tests_run + 1;
        end

        // Apply next test inputs
        if (count < TESTS) begin
          dut_g_in <= g_in[count];
          dut_p_in <= p_in[count];
          dut_a_in <= a_in[count];
        end

        if (count <= TESTS + latency) begin
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
        if (errors == 0) $display("  Result: ALL TESTS PASSED!");
        else $display("  Result: %0d FAILURES DETECTED!", errors);
        $display("=====================================");
        tests_run <= 0;  // Prevent repeated summary
      end
    end
  end
  /* verilator lint_on WIDTHTRUNC */

endmodule
/*verilator lint_on DECLFILENAME*/
