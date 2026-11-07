// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

// Flop with active-low asynchronous reset and a notifier, as in standard cell libraries
primitive udp_dffr(q, d, ck, rb, noti);
  output q;
  reg q;
  input d, ck, rb, noti;
  table
    // d ck rb noti : q : q+
    1 (01) 1 ? : ? : 1;
    0 (01) 1 ? : ? : 0;
    ? ? 0 ? : ? : 0;
    ? (?0) ? ? : ? : -;
    * b ? ? : ? : -;
    ? ? (?1) ? : ? : -;
    ? ? ? * : ? : x;
  endtable
endprimitive

// Flop with active-high asynchronous reset, level-sensitive line first
primitive udp_dffrh(q, d, ck, r);
  output q;
  reg q;
  input d, ck, r;
  table
    // d ck r : q : q+
    ? ? 1 : ? : 0;
    1 r 0 : ? : 1;
    0 r 0 : ? : 0;
    ? (?0) ? : ? : -;
    * ? ? : ? : -;
    ? ? (?0) : ? : -;
  endtable
endprimitive

// Flop with active-low asynchronous set and reset, reset dominates
primitive udp_dffsr(q, d, ck, sb, rb);
  output q;
  reg q;
  input d, ck, sb, rb;
  initial q = 1'b0;
  table
    // d ck sb rb : q : q+
    ? ? ? 0 : ? : 0;
    ? ? 0 1 : 0 : 1;
    ? ? 0 1 : 1 : -;
    1 r 1 1 : ? : 1;
    0 r 1 1 : ? : 0;
    ? (?0) ? ? : ? : -;
    * ? ? ? : ? : -;
    ? ? (?1) ? : ? : -;
    ? ? ? (?1) : ? : -;
  endtable
endprimitive

// Flop with active-low asynchronous set, holding the output with a '-' line
primitive udp_dffs(q, d, ck, sb);
  output q;
  reg q;
  input d, ck, sb;
  table
    // d ck sb : q : q+
    ? ? 0 : 0 : 1;
    ? ? 0 : 1 : -;
    0 r ? : ? : 0;
    1 r ? : ? : 1;
    ? (?0) ? : ? : -;
    * ? ? : ? : -;
    ? ? (?1) : ? : -;
  endtable
endprimitive

// Level-sensitive line testing no input
primitive udp_pulse(q, ck, d);
  output q;
  reg q;
  input ck, d;
  initial q = 1'b0;
  table
    // ck d : q : q+
    r ? : ? : 0;
    ? ? : 0 : 1;
  endtable
endprimitive

// Level-sensitive latch
primitive udp_latch(q, d, en);
  output q;
  reg q;
  input d, en;
  table
    // d en : q : q+
    1 1 : ? : 1;
    0 1 : ? : 0;
    ? 0 : ? : -;
    * 0 : ? : -;
  endtable
endprimitive

module t;
  logic ck = 1'b0;
  initial forever #5 ck = ~ck;

  logic d1 = 1'b1;
  logic rb1 = 1'b1;
  logic noti1 = 1'b0;
  wire q1;
  udp_dffr u_dffr (q1, d1, ck, rb1, noti1);
  logic sampled1;
  always @(negedge rb1) sampled1 = q1;
  initial begin
    @(posedge ck);
    #1 `checkd(q1, 1'b1);
    d1 = 1'b0;
    @(posedge ck);
    #1 `checkd(q1, 1'b0);
    d1 = 1'b1;
    @(posedge ck);
    #1 `checkd(q1, 1'b1);
    rb1 = 1'b0;
    #1 `checkd(q1, 1'b0);
    // Updated like the edges, so logic triggered by the reset sees the old value
    `checkd(sampled1, 1'b1);
    @(posedge ck);
    #1 `checkd(q1, 1'b0);
    rb1 = 1'b1;
    #1 `checkd(q1, 1'b0);
    @(posedge ck);
    #1 `checkd(q1, 1'b1);
    // The notifier line gives x (1 with --x-assign 1), but not under reset (IEEE 29.10)
    rb1 = 1'b0;
    #1 `checkd(q1, 1'b0);
    noti1 = 1'b1;
    #1 `checkd(q1, 1'b0);
    rb1 = 1'b1;
    #1 `checkd(q1, 1'b0);
    noti1 = 1'b0;
    #1 `checkd(q1, 1'b1);
  end

  logic d2 = 1'b1;
  logic r2 = 1'b0;
  wire q2;
  udp_dffrh u_dffrh (q2, d2, ck, r2);
  initial begin
    @(posedge ck);
    #1 `checkd(q2, 1'b1);
    r2 = 1'b1;
    #1 `checkd(q2, 1'b0);
    @(posedge ck);
    #1 `checkd(q2, 1'b0);
    r2 = 1'b0;
    #1 `checkd(q2, 1'b0);
    @(posedge ck);
    #1 `checkd(q2, 1'b1);
    d2 = 1'b0;
    @(posedge ck);
    #1 `checkd(q2, 1'b0);
  end

  logic d3 = 1'b0;
  logic sb3 = 1'b1;
  logic rb3 = 1'b1;
  wire q3;
  udp_dffsr u_dffsr (q3, d3, ck, sb3, rb3);
  initial begin
    @(posedge ck);
    #1 `checkd(q3, 1'b0);
    sb3 = 1'b0;
    #1 `checkd(q3, 1'b1);
    @(posedge ck);
    #1 `checkd(q3, 1'b1);
    rb3 = 1'b0;
    #1 `checkd(q3, 1'b0);
    // Releasing the reset while set is active sets again
    rb3 = 1'b1;
    #1 `checkd(q3, 1'b1);
    sb3 = 1'b1;
    #1 `checkd(q3, 1'b1);
    @(posedge ck);
    #1 `checkd(q3, 1'b0);
  end

  // Set held from time 0
  logic d5 = 1'b0;
  logic sb5 = 1'b0;
  logic rb5 = 1'b1;
  wire q5;
  udp_dffsr u_dffsr5 (q5, d5, ck, sb5, rb5);
  initial begin
    #1 `checkd(q5, 1'b1);
    sb5 = 1'b1;
    @(posedge ck);
    #1 `checkd(q5, 1'b0);
  end

  logic d7 = 1'b0;
  logic sb7 = 1'b1;
  wire q7;
  udp_dffs u_dffs (q7, d7, ck, sb7);
  initial begin
    @(posedge ck);
    #1 `checkd(q7, 1'b0);
    sb7 = 1'b0;
    #1 `checkd(q7, 1'b1);
    // The '-' line under set dominates the clock edge
    @(posedge ck);
    #1 `checkd(q7, 1'b1);
    sb7 = 1'b1;
    @(posedge ck);
    #1 `checkd(q7, 1'b0);
  end

  logic d6 = 1'b0;
  wire q6;
  udp_pulse u_pulse (q6, ck, d6);
  initial begin
    #1 `checkd(q6, 1'b1);
    @(posedge ck);
    #1 `checkd(q6, 1'b0);
    d6 = 1'b1;
    #1 `checkd(q6, 1'b1);
  end

  logic d4 = 1'b1;
  logic en4 = 1'b1;
  wire q4;
  udp_latch u_latch (q4, d4, en4);
  initial begin
    #1 d4 = 1'b0;
    #1 `checkd(q4, 1'b0);
    en4 = 1'b0;
    d4 = 1'b1;
    #1 `checkd(q4, 1'b0);
    en4 = 1'b1;
    #1 `checkd(q4, 1'b1);
  end

  initial begin
    #100;
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
