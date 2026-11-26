// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module t;
  bit clk = 0;
  always #5 clk = ~clk;
  int cyc = 0;
  always @(posedge clk) cyc <= cyc + 1;

  // Attempts start at cyc 2 and 8, and complete three cycles later
  int fails = 0;
  int passes = 0;
  int seq_passes = 0;
  assert property (@(posedge clk) (cyc == 2 || cyc == 8) |-> ##3 1'b0)
  else fails++;
  assert property (@(posedge clk) (cyc == 2 || cyc == 8) |-> ##3 1'b1) passes++;
  assert property (@(posedge clk) ((cyc == 1 || cyc == 7) ##1 (cyc == 2 || cyc == 8)) |-> ##3 1'b1)
    seq_passes++;

  int passes_at_ctl;
  int seq_passes_at_ctl;
  always @(negedge clk) begin
    case (cyc)
      3: begin
        // Vacuous successes pass
        `checkd(passes, 2);
        `checkd(seq_passes > 0, 1);
        passes_at_ctl = passes;
        seq_passes_at_ctl = seq_passes;
        $assertoff;
      end
      6: begin
        // Off starts no attempt, but the attempts already executing complete
        `checkd(fails, 1);
        `checkd(passes, passes_at_ctl + 1);
        `checkd(seq_passes, seq_passes_at_ctl + 1);
        $asserton;
      end
      9: begin
        passes_at_ctl = passes;
        seq_passes_at_ctl = seq_passes;
        $assertkill;
      end
      12: begin
        // Kill aborts the attempts already executing
        `checkd(fails, 1);
        `checkd(passes, passes_at_ctl);
        `checkd(seq_passes, seq_passes_at_ctl);
        $write("*-* All Finished *-*\n");
        $finish;
      end
      default: ;
    endcase
  end
endmodule
