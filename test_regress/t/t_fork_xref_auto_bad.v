// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// A hierarchical reference to an automatic variable (IEEE 1800-2023 6.21), of a
// block nested in a fork branch, moved into a task

module t;
  int r;
  initial begin
    fork
      begin : vb
        begin : mid
          automatic int w;
          w = 3;
          for (int i = 0; i < 1; i++) begin
            #1;
            r = mid.w;
          end
        end
      end
    join_none
    #10;
    $finish;
  end
endmodule
