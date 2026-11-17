// DESCRIPTION: Verilator: Selective assertion control by local and absolute names from instances of one module
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
    input bit [7:0] ctl
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
  if (1) begin : gen
    leaf c2 ();
  end
  int nb_failures = 0;
  initial begin : nb
    #1;
    check :
    assert (1'b0)
    else nb_failures++;
  end
  int tk_failures = 0;
  task automatic tk;
    check :
    assert (1'b0)
    else tk_failures++;
  endtask
  initial begin
    #1;
    tk();
  end
  // Local names resolve from the calling instance, upward names by searching upward from it,
  // and absolute names keep their meaning
  // (IEEE 1800-2023 20.11, 23.6, 23.8)
  initial begin
    if (ctl[0]) $assertoff(0, c);
    if (ctl[1]) $assertoff(0, nb);
    if (ctl[2]) $assertoff(0, t.m1.chk_blk);
    if (ctl[3]) $assertoff(0, tk);
    if (ctl[4]) $assertoff(0, gen.c2);
    if (ctl[5]) $assertoff(0, $root.t.m0.gen.c2);
    if (ctl[6]) $assertoff(0, m1.c);
    if (ctl[7]) $assertoff(0, m0.tk);
  end
endmodule

module t;
  mid m0 (.ctl(8'b01000111));
  mid m1 (.ctl(8'b10111000));
  initial begin
    #2;
    `checkd(m0.chk_blk.failures, 1);
    `checkd(m0.c.failures, 0);
    `checkd(m0.nb_failures, 0);
    `checkd(m0.tk_failures, 0);
    `checkd(m0.gen.c2.failures, 0);
    `checkd(m1.chk_blk.failures, 0);
    `checkd(m1.c.failures, 0);
    `checkd(m1.nb_failures, 1);
    `checkd(m1.tk_failures, 0);
    `checkd(m1.gen.c2.failures, 0);
    $display("*-* All Finished *-*");
    $finish;
  end
endmodule
