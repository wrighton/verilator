// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Hierarchical references to automatic variables from outside their scope
// (IEEE 1800-2023 6.21) in fork branches, moved into tasks: from a sibling
// block

module t;
  int r;
  initial begin
    fork
      begin : vb
        begin : sa
          automatic int w;
          w = 3;
        end
        begin : sb
          for (int i = 0; i < 1; i++) begin
            #1;
            r = sa.w;
          end
        end
      end
    join_none
    #10;
    $finish;
  end
endmodule
