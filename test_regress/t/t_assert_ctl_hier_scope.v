// DESCRIPTION: Verilator: Scoped assertion controls above hierarchical blocks
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module inner (
    input bit clk,
    input int cyc,
    output int fails
);
  /* verilator hier_block */
  int count = 0;
  assign fails = count;
  always @(posedge clk) begin
    inner_check : assert (cyc < 0) else count <= count + 1;
  end
endmodule

module leaf (
    input bit clk,
    input int cyc,
    output int fails,
    output int inner_fails
);
  /* verilator hier_block */
  int count = 0;
  assign fails = count;
  inner u_inner (.clk, .cyc, .fails(inner_fails));
  always @(posedge clk) begin
    leaf_check : assert (cyc < 0) else count <= count + 1;
  end
endmodule

module empty (
    input bit clk,
    output bit echoed
);
  /* verilator hier_block */
  assign echoed = clk;
endmodule

module mid (
    input bit clk,
    input int cyc,
    output int fails,
    output int leaf_fails,
    output int inner_fails
);
  int count = 0;
  assign fails = count;
  leaf u_leaf (.clk, .cyc, .fails(leaf_fails), .inner_fails);
  always @(posedge clk) begin
    mid_check : assert (cyc < 0) else count <= count + 1;
  end
endmodule

class Checker;
  int failures = 0;
  function void check(int cyc);
    assert (cyc < 0) else failures++;
  endfunction
endclass

module t;
  bit clk = 0;
  int cyc = 0;
  always #5 clk = ~clk;
  always @(posedge clk) cyc <= cyc + 1;

  int mid_fails;
  int leaf_fails;
  int inner_fails;
  mid u_mid (.clk, .cyc, .fails(mid_fails), .leaf_fails, .inner_fails);
  // A sibling outside the 'u_mid' scope
  int sib_fails;
  int sib_inner_fails;
  leaf u_sib (.clk, .cyc, .fails(sib_fails), .inner_fails(sib_inner_fails));
  bit echoed;
  empty u_empty (.clk, .echoed);
  // Scoped controls do not select assertions in class methods
  Checker chk = new;
  always @(posedge clk) chk.check(cyc);

  localparam int CYCLES = 4;
  // Failures added over CYCLES clock cycles by each assertion
  task automatic check_window(int mid_d, int leaf_d, int inner_d, int sib_d, int sib_inner_d);
    const int mid0 = mid_fails;
    const int leaf0 = leaf_fails;
    const int inner0 = inner_fails;
    const int sib0 = sib_fails;
    const int sib_inner0 = sib_inner_fails;
    const int chk0 = chk.failures;
    repeat (CYCLES) @(negedge clk);
    `checkd(mid_fails - mid0, mid_d);
    `checkd(leaf_fails - leaf0, leaf_d);
    `checkd(inner_fails - inner0, inner_d);
    `checkd(sib_fails - sib0, sib_d);
    `checkd(sib_inner_fails - sib_inner0, sib_inner_d);
    `checkd(chk.failures - chk0, CYCLES);
  endtask

  initial begin
    int levels;
    @(negedge clk);
    check_window(CYCLES, CYCLES, CYCLES, CYCLES, CYCLES);
    // The only top selects every assertion of the design
    $assertoff(0, t);
    check_window(0, 0, 0, 0, 0);
    $asserton(0, t);
    check_window(CYCLES, CYCLES, CYCLES, CYCLES, CYCLES);
    // A scope above some hierarchical blocks leaves the others enabled
    $assertoff(0, u_mid);
    check_window(0, 0, 0, CYCLES, CYCLES);
    $asserton(0, u_mid);
    // Levels limit the selection within and below the blocks
    $assertoff(1, u_mid);
    check_window(0, CYCLES, CYCLES, CYCLES, CYCLES);
    $asserton(0, t);
    $assertoff(2, t.u_mid);
    check_window(0, 0, CYCLES, CYCLES, CYCLES);
    $asserton(0, t);
    levels = cyc > 0 ? 3 : 0;
    $assertoff(levels, t);
    check_window(0, 0, CYCLES, 0, 0);
    $assertcontrol(3, 15, 7, levels + 1, t);
    check_window(CYCLES, CYCLES, CYCLES, CYCLES, CYCLES);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
