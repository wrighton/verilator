// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;
  string fmt;
  string s;
  int code;
  initial begin
    fmt = "%d %m";
    code = $sscanf("1 2", fmt, code, s);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
