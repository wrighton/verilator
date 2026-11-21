// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module sub (
    output o,
    input a
);
  assign o = a;
endmodule

interface ifc;
endinterface

module t;
  logic a = 1'b1;
  wire o1, o2;
  sub (strong0, weak1) u1 (o1, a);  // <--- Error: not a UDP
  sub (pull0, pull1) #() u2 (.o(o2), .a(a));  // <--- Error: not a UDP
  ifc (weak0, weak1) u3 ();  // <--- Error: not a UDP
endmodule
