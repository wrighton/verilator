// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module sub (
    input d,
    inout wire o
);
  assign (strong0, highz1) o = d;
endmodule

module t;
  reg [6:0] a = 0;
  reg [6:0] b = 0;
  reg d = 0;
  reg en = 0;

  // Open-drain wired-AND with a pullup
  wire [6:0] od;
  assign (strong0, highz1) od = a;
  assign (strong0, highz1) od = b;
  pullup (od);

  // highz0 against a weaker driver
  wire [6:0] hi;
  assign (highz0, strong1) hi = a;
  assign (weak0, weak1) hi = b;

  // Gates and net declaration assignment
  wire bh;
  buf (highz0, weak1) (bh, d);
  pulldown (bh);
  wire n;
  nor (highz1, strong0) (n, d, en);
  pullup (n);
  wire bt;
  bufif1 (strong0, highz1) (bt, d, en);
  pullup (bt);
  wire (pull0, highz1) nd = d;
  pullup (nd);

  // Open-drain drivers in submodules
  wire o;
  sub u1 (a[0], o);
  sub u2 (b[0], o);
  pullup (o);

  initial begin
    for (int i = 0; i < 20; ++i) begin
      a = 7'(i * 37 + 5);
      b = 7'(i * 91 + 3);
      d = i[0];
      en = i[1];
      #1;
      `checkh(od, a & b);
      `checkh(hi, a | b);
      `checkh(bh, d);
      `checkh(n, ~(d | en));
      `checkh(bt, en ? d : 1'b1);
      `checkh(nd, d);
      `checkh(o, a[0] & b[0]);
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
