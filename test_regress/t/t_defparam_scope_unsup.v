// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module sub;
  parameter S = 1;
  initial begin : sblk
    parameter P = 1;
  end
  defparam t.Q = 3;  // Unsupported, above the defparam
  defparam mid.M = 3;  // Unsupported, above the defparam, by module name
  defparam sub.S = 2;  // Unsupported, in the instance of the defparam, by module name
  defparam u.S = 2;  // Unsupported, in the instance of the defparam, by instance name
  defparam sblk.P = 2;  // Unsupported, in the instance of the defparam
endmodule

module mid;
  parameter M = 1;
  sub u ();
endmodule

module t;
  parameter Q = 1;
  mid m ();
  initial begin : tblk
    parameter P = 1;
  end
  defparam tblk.P = 2;  // Unsupported, in the instance of the defparam
  defparam t.Q = 2;  // Unsupported, in the instance of the defparam
endmodule
