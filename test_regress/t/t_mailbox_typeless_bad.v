// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;
  mailbox m;

  initial begin
    string s;
    int i;
    m = new;
    s = "hello";
    m.put(s);
    m.get(i);  // Type mismatch, run-time error
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
