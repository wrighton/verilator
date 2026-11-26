// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Hierarchical references to static variables of named blocks of fork branches,
// whose statements are moved into tasks

module other;
  int seen, seen_deep, seen_deeper;
  initial begin
    #3;
    seen = t.vb.x;
    seen_deep = t.vd.mid.y;
    seen_deeper = t.vd.mid.mid2.w;
  end
endmodule

module t;
  localparam realtime STEP = 1;
  int got_sib, got_rel, got_abs, got_any, got_cnt;
  int got_mid, got_mid_abs, got_mid2;
  int k;
  other u_other ();
  initial begin
    fork
      begin : vb
        int x;
        for (int i = 0; i < 2; i++) begin
          x = 7;
          #(STEP);
          got_rel = vb.x;  // From a block nested in the branch
          got_abs = t.vb.x;
        end
      end
      begin : sib
        for (int i = 0; i < 1; i++) begin
          #(2 * STEP);
          got_sib = t.vb.x;  // From another branch
        end
      end
      // Blocks nested in the branch, moved into its task with their statements
      begin : vd
        begin : mid
          static int y = 100;
          for (int i = 0; i < 2; i++) begin
            #(STEP);
            if (i == 1) y++;
            got_mid = mid.y;
            got_mid_abs = t.vd.mid.y;
          end
          begin : mid2
            int w;
            w = 3;
            got_mid2 = mid2.w + vd.mid.y;
          end
        end
      end
    join_none
    fork
      begin : va
        int y;
        for (int i = 0; i < 3; i++) y = y + 2;
      end
    join_any
    // A static variable is one variable for all processes of the branch,
    // initialized once (IEEE 1800-2023 6.21)
    for (k = 0; k < 3; k++) begin : lp
      fork
        begin : vc
          static int cnt = 10;
          for (int i = 0; i < 2; i++) begin
            #(STEP);
            if (i == 1) cnt++;
          end
        end
      join_none
    end
    #(10 * STEP);
    got_any = t.va.y;
    got_cnt = t.lp.vc.cnt;
    `checkd(got_cnt, 13);
    `checkd(got_mid, 101);
    `checkd(got_mid_abs, 101);
    `checkd(got_mid2, 3 + 101);
    `checkd(u_other.seen_deep, 101);
    `checkd(u_other.seen_deeper, 3);
    `checkd(u_other.seen, 7);
    `checkd(got_sib, 7);
    `checkd(got_rel, 7);
    `checkd(got_abs, 7);
    `checkd(t.vb.x, 7);
    `checkd(got_any, 6);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
