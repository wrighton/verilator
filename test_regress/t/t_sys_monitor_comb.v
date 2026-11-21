// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;

  int cnt = 0;
  bit en;

  // A $monitor under a condition in combinational logic
  always_comb begin
    en = cnt[0];
    if (en) $monitor("[%0t] cnt=%0d", $time, cnt);
  end

  initial begin
    repeat (4) #10 cnt = cnt + 1;
    #10;
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
