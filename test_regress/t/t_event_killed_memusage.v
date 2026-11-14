// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;
  event never;
  initial begin
    // Each disabled process waits on an event that never fires
    repeat (1000000) begin
      fork
        #1;
        @never;
      join_any
      disable fork;
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
