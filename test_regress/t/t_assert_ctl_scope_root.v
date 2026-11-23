// DESCRIPTION: Verilator: Selective assertion control through $root-anchored scopes
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

`timescale 1ns / 1ps

module sub;
  int failures = 0;
  int late_failures = 0;
  initial begin
    #1;
    check :
    assert (1'b0)
    else failures++;
    #3;
    late_check :
    assert (1'b0)
    else late_failures++;
  end
endmodule

`ifndef WHOLE_MODEL
module scope_off;
  initial $assertoff(0, $root.t.a);
endmodule
`endif

module t;
  sub a ();
  sub b ();
`ifdef WHOLE_MODEL
  localparam int ZERO = 0;
  for (genvar i = 0; i < 4; ++i) begin : whole
    initial $assertoff(0, $root.t);
  end
  initial begin
    $assertoff(0);
    $asserton(ZERO + 0);
    $assertoff(0, $root.t);
    #2;
    `checkd(a.failures, 0);
    `checkd(b.failures, 0);
    $asserton(0, t);
    #3;
    `checkd(a.late_failures, 1);
    `checkd(b.late_failures, 1);
    $display("*-* All Finished *-*");
    $finish;
  end
`else
  int top_failures = 0;
  scope_off ctl [2] ();
  if (1) begin : empty_scope
  end
  initial begin
    // Depth one reaches the top, not the two child instances.
    $assertoff(1, $root.t);
    #2;
    `checkd(a.failures, 0);
    `checkd(b.failures, 1);
    $assertoff(0, $root.t, $root.t.empty_scope);
    $assertoff(0, $root.t, $root.t.empty_scope);
    #2;
    top_check :
    assert (1'b0)
    else top_failures++;
    #1;
    `checkd(a.late_failures, 0);
    `checkd(b.late_failures, 0);
    `checkd(top_failures, 0);
    $display("*-* All Finished *-*");
    $finish;
  end
`endif
endmodule
