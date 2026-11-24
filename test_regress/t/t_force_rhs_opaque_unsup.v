// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module opaque_forcer;
  import "DPI-C" function logic unrepresented_value();
  initial begin
    #2 force t.n = unrepresented_value();
  end
endmodule

module t;
  logic enabled = 1;
  wire n;
  assign n = enabled ? 1'b1 : 1'bz;
  opaque_forcer u ();
  initial begin
    #1 force n = 1'bz;
    #4 enabled = 0;
  end
endmodule
