// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Hierarchical references to a variable of a named block in a fork branch, from
// another module and from a sibling branch's loop block, whose statements are
// moved into a task. Legal, but not supported, so reported as for a reference
// from outside the fork, rather than failing internally.

module other;
  int seen;
  initial begin
    #3;
    seen = t.vb.x;
  end
endmodule

module t;
  int got_sib;
  other u_other ();
  initial begin
    fork
      begin : vb
        int x;
        for (int i = 0; i < 2; i++) begin
          x = 7;
          #1;
        end
      end
      begin : sib
        for (int i = 0; i < 1; i++) begin
          #2;
          got_sib = t.vb.x;
        end
      end
    join_none
    #10;
    $finish;
  end
endmodule
