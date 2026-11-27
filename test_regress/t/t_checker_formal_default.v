// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// A checker formal argument stands for its actual, so before the first clock ticks $past and
// $stable of it use the default sampled value of the actual of each instance (IEEE 1800-2023
// 16.5.1, 17.3), whatever the values of unknown bits
checker c_f (logic clk, logic a, logic b);
  logic pa = 0;
  logic pb = 0;
  logic sa = 0;
  logic sb = 0;
  always_ff @(posedge clk) begin
    pa <= $past(a);
    pb <= $past(b);
    sa <= $stable(a);
    sb <= $stable(b);
  end
endchecker

// Instances with different defaults
checker c_n (logic clk, logic [6:0] a);
  logic [6:0] pa = 0;
  logic [6:0] pa2 = 0;
  always_ff @(posedge clk) begin
    pa <= $past(a);
    pa2 <= $past(a, 2);
  end
endchecker

// A formal passed on to a checker instance
checker c_in (logic clk, logic [6:0] a, output logic [6:0] pa);
  always_ff @(posedge clk) pa <= $past(a);
endchecker
checker c_out (logic clk, logic [6:0] b, output logic [6:0] pb);
  c_in u_in (clk, b, pb);
endchecker

module t;
  logic clk = 0;
  logic d0 = 0;
  logic d1 = 1;
  logic e0 = 0;
  logic e1 = 1;
  logic [6:0] n37a = 7'd37;
  logic [6:0] n37b = 7'd37;
  logic [6:0] n12 = 7'd12;
  logic [6:0] n109 = 7'd109;
  localparam logic [6:0] NP = 7'd55;
  logic [6:0] ng[2] = '{7'd66, 7'd77};
  c_f u_d (clk, d0, d1);
  c_f u_e (clk, e0, e1);  // Actuals with the same defaults
  c_n u_n37a (clk, n37a);
  c_n u_n37b (clk, n37b);
  c_n u_n12 (clk, n12);
  c_n u_n109 (clk, n109);
  c_n u_np (clk, NP);  // A parameter
  c_n u_ng (clk, ng[1]);  // An element of an unpacked array
  logic [6:0] o21a = 7'd21;
  logic [6:0] o42 = 7'd42;
  logic [6:0] o21b = 7'd21;
  logic [6:0] po21a;
  logic [6:0] po42;
  logic [6:0] po21b;
  c_out u_o21a (clk, o21a, po21a);
  c_out u_o42 (clk, o42, po42);
  c_out u_o21b (clk, o21b, po21b);
  initial begin
    // Changed before the first edge, so the defaults differ from the sampled values
    #2;
    n37a = 7'd1;
    n37b = 7'd2;
    n12 = 7'd3;
    n109 = 7'd4;
    d0 = 1'b1;
    d1 = 1'b0;
    e0 = 1'b1;
    e1 = 1'b0;
    o21a = 7'd5;
    o42 = 7'd6;
    o21b = 7'd7;
    #3 clk = 1'b1;
    #1;
    `checkh(u_d.pa, 1'b0);
    `checkh(u_d.pb, 1'b1);
    `checkh(u_d.sa, 1'b0);
    `checkh(u_d.sb, 1'b0);
    `checkh(u_e.pa, 1'b0);
    `checkh(u_e.pb, 1'b1);
    `checkh(u_e.sa, 1'b0);
    `checkh(u_e.sb, 1'b0);
    `checkh(u_n37a.pa, 7'd37);
    `checkh(u_n37b.pa, 7'd37);
    `checkh(u_n12.pa, 7'd12);
    `checkh(u_n109.pa, 7'd109);
    `checkh(u_n12.pa2, 7'd12);
    `checkh(u_n109.pa2, 7'd109);
    `checkh(u_np.pa, 7'd55);
    `checkh(u_ng.pa, 7'd77);
    `checkh(po21a, 7'd21);
    `checkh(po42, 7'd42);
    `checkh(po21b, 7'd21);
    // At the second edge, the past value is sampled and the one before it the default
    #4 clk = 1'b0;
    #5 clk = 1'b1;
    #1;
    `checkh(u_n37a.pa, 7'd1);
    `checkh(u_n37b.pa, 7'd2);
    `checkh(u_n12.pa, 7'd3);
    `checkh(u_n109.pa, 7'd4);
    `checkh(u_n37a.pa2, 7'd37);
    `checkh(u_n12.pa2, 7'd12);
    `checkh(u_n109.pa2, 7'd109);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
