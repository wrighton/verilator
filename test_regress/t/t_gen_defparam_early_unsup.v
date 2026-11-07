// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilator lint_off DEFPARAM

module t;
  m1 n ();
  m3 x ();
  m4 y ();
endmodule

// IEEE 1800-2023 23.10.4.2 example
module m1;
  parameter p = 2;
  defparam t.n.p = 1;  // Unsupported, 't' is not elaborated, but is also the top module
  if (p == 1) begin : t
    m2 n ();
  end
endmodule

module m2;
  parameter p = 3;
endmodule

module m3;
  m2 n ();
  defparam x.n.p = 4;  // Unsupported, 'x' is not elaborated, but is also the instance of m3
  if (0) begin : x
    m2 n ();
  end
endmodule

module m4;
  parameter C = 0;
  m2 n ();
  defparam y.n.p = 5;  // Unsupported, 'y' is not elaborated, but is also the instance of m4
  case (C)
    1: begin : y
      m2 n ();
    end
    default: ;
  endcase
endmodule
