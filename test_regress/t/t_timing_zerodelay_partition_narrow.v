// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Clocked processes run before the processes resumed from a #0 delay accessing what they
// access, while others, accessing the same variables of other instances, or with outputs
// when the code after the #0 has none, may run later

interface ifc;
  int sig = 0;
endinterface

module counter (
    input logic clk,
    output int seen
);
  /*verilator no_inline_module*/
  int x = 0;
  initial seen = 0;
  always @(posedge clk) seen <= x;
endmodule

module t;
  logic clk = 1'b0;

  // An instance a virtual interface refers to, and one no reference is made to
  ifc i ();
  ifc j ();
  virtual ifc vi = i;
  int seen_i = 0;
  int seen_j = 0;
  always @(posedge clk) seen_i <= i.sig;
  always @(posedge clk) seen_j <= j.sig;

  // The variable of one instance of a module written after a #0, of another not
  int seen1;
  int seen2;
  counter u1 (
      .clk(clk),
      .seen(seen1)
  );
  counter u2 (
      .clk(clk),
      .seen(seen2)
  );

  // Output of a clocked process, while the code after the #0 has none
  int cyc = 0;
  always @(posedge clk) begin
    ++cyc;
    if (cyc > 10) $write("%%Error: Too many cycles\n");
  end

  always @(posedge clk) begin
    #0;
    vi.sig = vi.sig + 1;
    u1.x = u1.x + 1;
  end

  initial begin
    for (int n = 1; n <= 4; ++n) begin
      #5 clk = 1'b1;
      #5 clk = 1'b0;
      `checkd(seen_i, n - 1);
      `checkd(seen_j, 0);
      `checkd(seen1, n - 1);
      `checkd(seen2, 0);
      `checkd(cyc, n);
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
