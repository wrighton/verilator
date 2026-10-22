// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2025 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0x exp=%0x (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

interface my_if #(
    parameter WIDTH = 1
);
  logic [WIDTH-1:0] sig_a, sig_b, sig_c, sig_d;
  logic [WIDTH-1:0] sig_e, sig_f;
  // Multiple expressions same direction
  logic [WIDTH-1:0] m1, m2, m3;

  modport mp1(input .a(sig_a), output .b(sig_b));
  modport mp2(input .a(sig_c), output .b(sig_d));
  // Mixed regular and expression items
  modport mp3(input sig_e, output .f(sig_f));
  // Multiple expressions with same direction
  modport mp4(input .in1(m1), input .in2(m2), output .out(m3));
endinterface

module mod1 (
    my_if.mp1 i
);
  assign i.b = i.a;
endmodule

module mod2 (
    my_if.mp2 i
);
  assign i.b = i.a;
endmodule

module mod3 (
    my_if.mp3 i
);
  assign i.f = i.sig_e;  // sig_e is regular, f is expression
endmodule

module mod4 (
    my_if.mp4 i
);
  assign i.out = i.in1 ^ i.in2;
endmodule

// Multiple instances of the interface, including interface array elements
interface my_if5;
  logic [6:0] d;
  logic [6:0] q;
  modport mp(input .ali(d), output .alo(q));
endinterface

module mod5 (
    my_if5.mp i
);
  assign i.alo = i.ali + 7'h1;
endmodule

module top ();
  my_if #(.WIDTH(8)) myIf ();
  assign myIf.sig_a = 8'h42, myIf.sig_c = 8'hAB;
  assign myIf.sig_e = 8'hCD;
  assign myIf.m1 = 8'hF0, myIf.m2 = 8'h0F;

  mod1 mod1i (myIf.mp1);
  mod2 mod2i (myIf.mp2);
  mod3 mod3i (myIf.mp3);
  mod4 mod4i (myIf.mp4);

  my_if5 if5a ();
  my_if5 if5b ();
  my_if5 if5arr[3:1] ();
  mod5 mod5a (.i(if5a));
  mod5 mod5b (.i(if5b));
  mod5 mod5arr3 (.i(if5arr[3]));
  mod5 mod5arr1 (.i(if5arr[1]));
  initial begin
    for (int n = 0; n < 4; ++n) begin
      if5a.d = 7'(n * 3 + 1);
      if5b.d = 7'(n * 5 + 2);
      if5arr[3].d = 7'(n * 7 + 3);
      if5arr[1].d = 7'(n * 11 + 4);
      #1;
      `checkh(if5a.q, 7'(n * 3 + 2));
      `checkh(if5b.q, 7'(n * 5 + 3));
      `checkh(if5arr[3].q, 7'(n * 7 + 4));
      `checkh(if5arr[1].q, 7'(n * 11 + 5));
    end
  end

  initial begin
    #1;
    `checkh(myIf.sig_b, 8'h42);  // mp1: b = a
    `checkh(myIf.sig_d, 8'hAB);  // mp2: b = a
    `checkh(myIf.sig_f, 8'hCD);  // mp3: f = sig_e
    `checkh(myIf.m3, 8'hFF);  // mp4: out = in1 ^ in2
    #10;
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
