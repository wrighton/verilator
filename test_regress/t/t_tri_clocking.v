// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

interface wb_ifc;
  logic clk;
  wire rst;
  tri0 cyc;
  clocking mck @(posedge clk);
    input rst;
    output cyc;
  endclocking
endinterface

// The initializer of an output clockvar reads its net, it does not drive it
interface pull_ifc (
    input logic clk
);
  tri1 [6:0] v;
  tri0 [6:0] w;
  clocking cb @(posedge clk);
    output v, w;
  endclocking
endinterface

module t;
  wb_ifc wb_ma ();

  logic clk = 0;
  always #5 clk = ~clk;

  // Test: pulled nets with clocking outputs before and after the first drive
  pull_ifc ip (clk);
  initial begin
    logic [6:0] d;
    #1;
    `checkh(ip.v, 7'h7f);
    `checkh(ip.w, 7'h00);
    repeat (3) begin
      @(negedge clk);
      d = 7'($random);
      ip.cb.v <= d;
      ip.cb.w <= ~d;
      @(posedge clk);
      #1;
      `checkh(ip.v, d);
      `checkh(ip.w, ~d);
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
