// DESCRIPTION: Verilator: Selective pass-action control of a cover statement
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__, `__LINE__, (gotv), (expv)); `stop; end while (0);
// verilog_format: on

module cov_leaf (
    input clk,
    input int cyc
);
  int cov_hits = 0;
  // Every attempt succeeds, so the pass statement runs once per attempt
  cov_check :
  cover property (@(posedge clk) cyc >= 0) cov_hits++;
endmodule

module t (
    input clk
);
  int cyc = 0;
  int phase = 0;
  int last_a = 0;
  int last_b = 0;
  cov_leaf a (
      clk,
      cyc
  );
  cov_leaf b (
      clk,
      cyc
  );

  // The oracle deliberately uses if/stop, never an assertion subject to control.
  task automatic check_deltas(int ah, int bh);
    `checkd(a.cov_hits - last_a, ah);
    `checkd(b.cov_hits - last_b, bh);
  endtask

  always @(negedge clk) begin
    cyc++;
    // Each phase lasts two cycles; only the second is checked
    if (cyc >= 3 && cyc % 2 == 1) begin
      case (phase)
        0: begin
          check_deltas(1, 1);
          $assertcontrol(7, 1, 2, 0, a.cov_check);  // PassOff, cover directive, a only
        end
        1: begin
          check_deltas(0, 1);
          $assertcontrol(6, 1, 2, 0, a.cov_check);  // PassOn, cover directive, a only
        end
        default: begin
          check_deltas(1, 1);
          $write("*-* All Finished *-*\n");
          $finish;
        end
      endcase
      phase++;
    end
    last_a = a.cov_hits;
    last_b = b.cov_hits;
  end
endmodule
