// DESCRIPTION: Verilator: Selective assertion control by relative names from instances of one module
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
    input bit off_blk,
    input bit off_cell
);
  if (1) begin : chk_blk
    int failures = 0;
    initial begin
      #1;
      check :
      assert (1'b0)
      else failures++;
    end
  end
  leaf c ();
  // Relative names resolve from the calling instance (IEEE 1800-2023 20.11, 23.8)
  initial begin
    if (off_blk) $assertoff(0, chk_blk);
    if (off_cell) $assertoff(0, c);
  end
endmodule

module t;
  mid m0 (
      .off_blk(1'b1),
      .off_cell(1'b0)
  );
  mid m1 (
      .off_blk(1'b0),
      .off_cell(1'b1)
  );
  initial begin
    #2;
    `checkd(m0.chk_blk.failures, 0);
    `checkd(m0.c.failures, 1);
    `checkd(m1.chk_blk.failures, 1);
    `checkd(m1.c.failures, 0);
    $display("*-* All Finished *-*");
    $finish;
  end
endmodule
