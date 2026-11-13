// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

typedef chandle ch_t;

interface ifc (
    input chandle i  // BAD: port
);
endinterface

module sub (
    input ch_t a,  // BAD: port
    output chandle b[2]  // BAD: port
);
endmodule

module t;
  // Legal uses
  import "DPI-C" function chandle mk(input chandle x, output chandle y);
  function automatic chandle f(input chandle x, ref chandle r);
    return x;
  endfunction
  chandle c = null;
  chandle d;
  chandle arr[2];
  bit b;
  initial d = c;
  always @(c == d) b = 1;

  // Illegal uses
  ifc ifc (.i(c));
  sub sub (.a(c), .b(arr));
  assign d = c;  // BAD: continuous assignment
  assign arr[0] = c;  // BAD: continuous assignment
  always @(c) b = 1;  // BAD: event control
  always @(posedge d) b = 1;  // BAD: event control
endmodule
