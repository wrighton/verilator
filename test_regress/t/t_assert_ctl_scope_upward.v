// DESCRIPTION: Verilator: Selective assertion control by upward names from a module under several parents
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

`timescale 1ns / 1ps

module leaf;
  int failures = 0;
  initial begin
    #1;
    check :
    assert (1'b0)
    else failures++;
  end
endmodule

module mid (
    input bit off_cell,
    input bit off_blk
);
  // An upward name through the parent's module name names that parent instance
  // (IEEE 1800-2023 23.8)
  initial begin
    if (off_cell) $assertoff(0, par.sib);
    if (off_blk) $assertoff(0, par.gb);
  end
endmodule

module par (
    input bit off_cell,
    input bit off_blk
);
  leaf sib ();
  if (1) begin : gb
    int failures = 0;
    initial begin
      #1;
      check :
      assert (1'b0)
      else failures++;
    end
  end
  mid m (
      .off_cell,
      .off_blk
  );
endmodule

// Differently elaborated parents holding the same instance target
module midv (
    input bit off
);
  initial if (off) $assertoff(0, parv.sib);
endmodule

module parv #(
    parameter int N = 1
);
  for (genvar i = 0; i < N; ++i) begin : g
    leaf l ();
  end
  leaf sib ();
  midv m (.off(N == 1));
endmodule

module t;
  par p0 (
      .off_cell(1'b1),
      .off_blk(1'b0)
  );
  par p1 (
      .off_cell(1'b0),
      .off_blk(1'b1)
  );
  par p2 (
      .off_cell(1'b0),
      .off_blk(1'b0)
  );
  par p3 (
      .off_cell(1'b1),
      .off_blk(1'b1)
  );
  parv #(.N(1)) v0 ();
  parv #(.N(2)) v1 ();
  initial begin
    #2;
    `checkd(v0.sib.failures, 0);
    `checkd(v1.sib.failures, 1);
    `checkd(p0.sib.failures, 0);
    `checkd(p0.gb.failures, 1);
    `checkd(p1.sib.failures, 1);
    `checkd(p1.gb.failures, 0);
    `checkd(p2.sib.failures, 1);
    `checkd(p2.gb.failures, 1);
    `checkd(p3.sib.failures, 0);
    `checkd(p3.gb.failures, 0);
    $display("*-* All Finished *-*");
    $finish;
  end
endmodule
