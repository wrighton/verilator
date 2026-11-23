// DESCRIPTION: Verilator: Selective assertion control with the levels argument omitted
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

module mid;
  leaf l ();
endmodule

module t;
  localparam logic [1:0] IDX = 2'b01;
  localparam int INDEX_TABLE [0:1] = '{0, 1};
  logic width_probe;
  mid a ();
  mid b ();
  leaf neg[-1:-2] ();
  leaf pos[1:0] ();
  leaf bits_target[1:0] ();
  leaf param_target[1:0] ();
  leaf enum_target[1:0] ();
  if (1) begin : cfg
    typedef enum int { SELECTED = 1 } index_t;
  end
  initial begin
    // An omitted levels argument selects every level below the scope (IEEE 1800-2023 20.11)
    $assertcontrol(4, 15, 7,, t.a);
    $assertoff(0, neg[int'(-1)].check);
    $assertoff(0, pos[IDX[0]].check);
    $assertoff(0, bits_target[$bits(width_probe)].check);
    $assertoff(0, param_target[INDEX_TABLE[1]].check);
    $assertoff(0, enum_target[int'(cfg.SELECTED)].check);
    #2;
    `checkd(a.l.failures, 0);
    `checkd(b.l.failures, 1);
    `checkd(neg[-1].failures, 0);
    `checkd(neg[-2].failures, 1);
    `checkd(pos[1].failures, 0);
    `checkd(pos[0].failures, 1);
    // Ordinary hierarchical reads and assertion selectors use the same index expressions.
    `checkd(bits_target[$bits(width_probe)].failures, 0);
    `checkd(bits_target[0].failures, 1);
    `checkd(param_target[INDEX_TABLE[1]].failures, 0);
    `checkd(param_target[0].failures, 1);
    `checkd(enum_target[1].failures, 0);
    `checkd(enum_target[0].failures, 1);
    $display("*-* All Finished *-*");
    $finish;
  end
endmodule
