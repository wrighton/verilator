// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// A disable of the outermost scope of a procedure flushes its pending violation report
// (IEEE 1800-2023 16.4.4, 12.5.3.1)
module t;
  logic [1:0] sel = 2'b01;
  logic go = 1'b0;
  int y;
  always @(sel) begin : b
    unique case (1'b1)
      sel[0]: y = 1;
      sel[1]: y = 2;
    endcase
  end
  always @(go) begin : kill_b
    disable b;
  end
  initial begin
    #1;
    sel = 2'b11;  // Violation, then 'b' is disabled: not reported
    go <= 1'b1;
    #1;
    sel = 2'b01;
    #1;
    sel = 2'b11;  // Reported
    #1;
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
