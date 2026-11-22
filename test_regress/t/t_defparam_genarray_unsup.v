// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module sub;
  parameter P = 1;
endmodule

module wrap;
  sub u_arr[2] ();
endmodule

module t;
  localparam IDX = 1;
  sub u_arr[2] ();
  sub u_arr2[2][2] ();
  wrap u_wrap ();
  for (genvar i = 0; i < 2; ++i) begin : g
    sub u ();
  end
  defparam u_arr[1].P = 2;  // Element of an instance array
  defparam u_wrap.u_arr[0].P = 2;  // Element of an instance array, below
  defparam g[IDX].u.P = 3;  // Select by parameter
  defparam g[0].u[IDX].P = 3;  // Select by parameter, below
  defparam u_arr2[1][0].P = 4;  // Multiple selects
  defparam g[1'bx].u.P = 5;  // Unknown select
  defparam g[1.0].u.P = 5;  // Real select
  defparam g[null].u.P = 5;  // Null select
  defparam g[40'h1_0000_0001].u.P = 5;  // Wider than 32 bits, outside the 32-bit range
  // Through generate blocks of the same name, found as a generate block
  for (genvar i = 0; i < 2; ++i) begin : gp
    if (i == 0) begin : alt
      sub u ();
    end else begin : alt
      if (1) begin : u
      end
    end
  end
  defparam gp[0].alt.u.P = 6;
  // Through generate blocks of the same name, from outside the scope
  for (genvar i = 0; i < 2; ++i) begin : g2
    if (i == 0) begin : alt
      sub u ();
    end else begin : alt
      sub u ();
    end
  end
  cfg c ();
endmodule

module cfg;
  defparam t.g2[0].alt.u.P = 3;
endmodule
