// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;
  mailbox m1;
  std::mailbox m2;
  mailbox #() m3;
  mailbox #(int) m4;

  initial begin
    m1 = new;
    m1.put(5);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
