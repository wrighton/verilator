// DESCRIPTION: Verilator: Overlapping scopes of a control above hierarchical blocks
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module child (
    input bit clk,
    output int fails
);
  int count = 0;
  assign fails = count;
  always @(posedge clk) begin
    child_check : assert (1'b0) else count <= count + 1;
  end
endmodule

module block (
    input bit clk,
    output int fails,
    output int child_fails
);
  /* verilator hier_block */
  int count = 0;
  assign fails = count;
  child c (.clk, .fails(child_fails));
  always @(posedge clk) begin
    block_check : assert (1'b0) else count <= count + 1;
  end
endmodule

module mid (
    input bit clk,
    output int fails,
    output int child_fails
);
  block b (.clk, .fails, .child_fails);
endmodule

module cm (
    input bit clk,
    output int fails,
    output int child_fails
);
  mid m1 (.clk, .fails, .child_fails);
  // Resolved from each instance of this module
  task automatic off4();
    $assertoff(4, t, m1);
  endtask
endmodule

module t;
  bit clk = 0;
  int cyc = 0;
  always #5 clk = ~clk;
  always @(posedge clk) cyc <= cyc + 1;

  // Failures of the block and child assertions of each block instance
  int fails[8];
  mid u_mid (.clk, .fails(fails[0]), .child_fails(fails[1]));
  // Below the first scope only
  block u_sib (.clk, .fails(fails[2]), .child_fails(fails[3]));
  // A module instantiated more than once, holding a control
  cm c1 (.clk, .fails(fails[4]), .child_fails(fails[5]));
  cm c2 (.clk, .fails(fails[6]), .child_fails(fails[7]));

  localparam int CYCLES = 4;
  localparam int C = CYCLES;
  // Failures added over CYCLES clock cycles by each assertion
  task automatic check_window(int expected[8]);
    int start[8];
    start = fails;
    repeat (CYCLES) @(negedge clk);
    for (int i = 0; i < 8; ++i) `checkd(fails[i] - start[i], expected[i]);
  endtask

  initial begin
    int levels;
    @(negedge clk);
    // Each assertion is selected at its smallest depth below any of the scopes
    $asserton(0, t);
    $assertoff(2, t, u_mid);
    check_window('{0, C, 0, C, C, C, C, C});
    $asserton(0, t);
    $assertoff(2, u_mid, t);
    check_window('{0, C, 0, C, C, C, C, C});
    $assertoff(0, t);
    $asserton(2, t, u_mid);
    check_window('{C, 0, C, 0, 0, 0, 0, 0});
    $asserton(0, t);
    $assertcontrol(4, 15, 7, 2, t, u_mid);
    check_window('{0, C, 0, C, C, C, C, C});
    $asserton(0, t);
    levels = cyc > 0 ? 2 : 0;
    $assertoff(levels, t, u_mid);
    check_window('{0, C, 0, C, C, C, C, C});
    $asserton(0, t);
    $assertoff(3, t, u_mid);
    check_window('{0, 0, 0, 0, C, C, C, C});
    $asserton(0, t);
    c1.off4();
    check_window('{0, 0, 0, 0, 0, 0, 0, C});
    $asserton(0, t);
    $assertoff(4, t, c2.m1);
    check_window('{0, 0, 0, 0, 0, C, 0, 0});
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
