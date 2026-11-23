// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0)
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0)
`define checkr(gotv,expv) do if ((gotv) != (expv)) begin $write("%%Error: %s:%0d:  got=%f exp=%f\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0)
// verilog_format: on

// A force keeps evaluating its value (IEEE 1800-2023 10.6.2), also when the forced variable
// can be forced and read through the VPI. The .vlt files make 'y', 'w', 'v' and 'r' so.

`timescale 1ns / 1ns

module t;
  int vpi_changes = 0;  // Value changes of 'y' seen through the VPI, written by the VPI

  // A force with a value that keeps changing, under a control that changes
  logic src = 1'b0;
  always #1 src = ~src;
  logic drv = 1'b0;
  logic y;
  assign y = drv;
  bit en = 1'b0;
  always @(en) begin
    if (en) force y = src;
    else release y;
  end
  int edges = 0;
  always @(posedge y) ++edges;
  initial begin
    #5 en = 1'b1;
    #50;
    `checkd(edges, 25);
    // Each of its 50 toggles was seen through the VPI too
    `checkd(vpi_changes, 50);
    en = 1'b0;
    #1;
    `checkh(y, drv);
    begin
      automatic int released_edges = edges;
      #4;
      `checkd(edges, released_edges);
    end
  end

  // A force and a release through the VPI (at 11, 17 and 27 ns, by the .cpp) override a
  // force in code, as a later force or release does
  logic wsrc = 1'b0;
  always #2 wsrc = ~wsrc;
  logic wdrv = 1'b1;
  logic w;
  assign w = wdrv;
  initial begin
    #5 force w = wsrc;
    #8 `checkh(w, 1'b0);  // The VPI forced 0 at 11 ns, while 'wsrc' was 1
    #2 `checkh(w, 1'b0);
    #4 `checkh(w, wdrv);  // The VPI released it at 17 ns
    #3 force w = wsrc;
    #3 `checkh(w, wsrc);
    #4 `checkh(w, wdrv);  // The VPI released the force in code at 27 ns
    #4 `checkh(w, wdrv);
  end

  // Overlapping and partial forces, each keeping only the bits no later force or release took
  logic [7:0] a = 8'h00;
  logic [7:0] b = 8'h00;
  always #1 a = a + 8'd3;
  always #1 b = b - 8'd5;
  logic [7:0] vdrv = 8'h5a;
  logic [7:0] v;
  assign v = vdrv;
  initial begin
    #2 force v = a;
    #3 `checkh(v, a);
    force v[3:0] = b[3:0];
    #3 `checkh(v, {a[7:4], b[3:0]});
    release v[3:0];
    #3 `checkh(v, {a[7:4], vdrv[3:0]});
    release v;
    #3 `checkh(v, vdrv);
  end

  // A forced value of a type without bits
  real rsrc = 0.0;
  always #1 rsrc = rsrc + 1.5;
  real rdrv = -1.0;
  real r;
  assign r = rdrv;
  initial begin
    #3 force r = rsrc;
    #5 `checkr(r, rsrc);
    release r;
    #2 `checkr(r, rdrv);
  end

  initial begin
    #70;
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
