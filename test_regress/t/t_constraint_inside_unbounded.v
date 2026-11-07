// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// A class parameter of '$' may bound an 'inside' range (IEEE 1800-2023 6.20.2.1)
class Cls #(
    parameter int MAX = $
);
  rand int x;
  constraint c_range {
    x inside {[1 : MAX]};
    x < 100;
  }
endclass

module t;
  Cls c_unb = new;
  Cls #(5) c_max = new;
  bit above_five = 0;

  initial begin
    repeat (50) begin
      if (c_unb.randomize() != 1) $stop;
      if (c_unb.x < 1 || c_unb.x >= 100) $stop;
      if (c_unb.x > 5) above_five = 1;
      if (c_max.randomize() != 1) $stop;
      if (c_max.x < 1 || c_max.x > 5) $stop;
    end
    if (!above_five) $stop;
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
