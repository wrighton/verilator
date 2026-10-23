// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilator lint_off DEFPARAM

module t;
  m1 n ();
  m3 x ();
endmodule

// IEEE 1800-2023 23.10.4.2 example
module m1;
  parameter p = 2;
  defparam t.n.p = 1;  // Bad
  if (p == 1) begin : t
    m2 n ();
  end
endmodule

module m2;
  parameter p = 3;
endmodule

module m3;
  m2 n ();
  defparam x.n.p = 4;  // Bad, 'x' is also the instance of m3
  if (1) begin : x
    m2 n ();
  end
  defparam g.n.p = 5;
  if (1) begin : g
    m2 n ();
    m2 n2 ();
    defparam g.n2.p = 6;
  end
endmodule
