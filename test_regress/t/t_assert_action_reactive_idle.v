// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Actions of concurrent assertions, only some failing, of many instances: what runs the actions
// in the Reactive region has no work while none is pending

module chk (
    input clk,
    input [6:0] a,
    input int cyc,
    output int fails
);
  assert property (@(posedge clk) a != 7'h7f)
  else ++fails;
  assert property (@(posedge clk) a != 7'h7e)
  else ++fails;
  assert property (@(posedge clk) cyc != -5)
  else ++fails;
endmodule

module t;
  bit clk = 0;
  always #5 clk = ~clk;

  bit [6:0] a = 0;
  int cyc = 0;
  always @(posedge clk) begin
    a <= a + 7'd1;
    cyc <= cyc + 1;
  end

  localparam int N = 7;
  int fails[N];
  for (genvar i = 0; i < N; ++i) begin : g
    chk u (.clk(clk), .a(a), .cyc(cyc), .fails(fails[i]));
  end

  // Ticks noting a pending action, once its actions ran
  int noted = 0;
`ifdef VERILATOR
  always @(negedge clk) noted += $c32("vlSymsp->__Vm_assertActionPending.load()");
`endif

  initial begin
    repeat (300) @(posedge clk);
    #1;
    // a is 7f and 7e on 2 ticks each in 300
    for (int i = 0; i < N; ++i) `checkd(fails[i], 4);
    `checkd(noted, 0);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
