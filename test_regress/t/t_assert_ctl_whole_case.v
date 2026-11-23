// DESCRIPTION: Verilator: Whole-model selection leaves untyped checks unchanged
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;
  bit [1:0] sel = 2;
  int result;
  initial begin
    $asserton(0, $root.t);
    // Synthesis-only checks have no assertion type and are not selected.
    case (sel)  // verilator full_case
      0: result = 1;
    endcase
    if (result != 0) $stop;
    $display("*-* All Finished *-*");
    $finish;
  end
endmodule
