// DESCRIPTION: Verilator: Global assertion Off preserves a running NFA attempt
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__, `__LINE__, (gotv), (expv)); `stop; end while (0);
// verilog_format: on

module t;
  bit clk = 0;
  always #1 clk = ~clk;
  int cyc = 0;
  int failures = 0;
  int split_passes = 0;
  int unsplit_passes = 0;
  int running_passes = 0;
  int running_unsplit_passes = 0;
  int split_before_off;
  int unsplit_before_off;
  int running_before_off;
  int running_unsplit_before_off;
  wire go = cyc > 20;

`ifdef SEED_CONTROL
  // An unrelated, unexecuted scope control must not change global Off.
  other :
  assert property (@(posedge clk) 1'b1);
  initial if (1'b0) $assertoff(0, t.other);
`endif

  check_late :
  assert property (@(posedge clk) (cyc == 2 || cyc == 5) |-> ##2 1'b0)
  else failures++;

  assert property (@(posedge clk) go |-> ##2 1'b1) split_passes++;
  assert property (@(posedge clk) (go ##1 go) |-> ##2 1'b1) unsplit_passes++;
  assert property (@(posedge clk) (cyc == 2) |-> ##2 1'b1) running_passes++;
  assert property (@(posedge clk) ((cyc == 1) ##1 (cyc == 2)) |-> ##2 1'b1)
    running_unsplit_passes++;

  always @(posedge clk) cyc <= cyc + 1;
  always @(negedge clk) begin
    case (cyc)
      3: begin
        `checkd(split_passes > 0, 1);
        `checkd(unsplit_passes > 0, 1);
        split_before_off = split_passes;
        unsplit_before_off = unsplit_passes;
        running_before_off = running_passes;
        running_unsplit_before_off = running_unsplit_passes;
        $assertoff;
      end
      6, 9: begin
        // No new attempts report. The attempts already running report once.
        `checkd(split_passes, split_before_off);
        `checkd(unsplit_passes, unsplit_before_off);
        `checkd(running_passes, running_before_off + 1);
        `checkd(running_unsplit_passes, running_unsplit_before_off + 1);
        `checkd(failures, 1);
        if (cyc == 9) begin
          $write("*-* All Finished *-*\n");
          $finish;
        end
      end
      default: begin
      end
    endcase
  end
endmodule
