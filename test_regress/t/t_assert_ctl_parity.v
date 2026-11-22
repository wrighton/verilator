// DESCRIPTION: Verilator: Scoped controls do not change global assertion control semantics
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
  int cyc = 0;
  int failures = 0;
  int split_passes = 0;
  int unsplit_passes = 0;
  int late_split = 0;
  int late_unsplit = 0;
  int split_at_off;
  int unsplit_at_off;
  int late_split_at_off;
  int late_unsplit_at_off;
  int deferred_sum = 0;
  int payload = 3;
  wire go = cyc > 20;

  initial begin
`ifdef SEED_CONTROL
    // Select the tested sites without changing their unlocked state.
    let UNLOCK = 2;
    let SV_ASSERT_TYPES = 15;
    let ALL_DIRECTIVES = 7;
    $assertcontrol(UNLOCK, SV_ASSERT_TYPES, ALL_DIRECTIVES, 0, t);
`endif
    for (int i = 0; i < 2; ++i) begin
      assert #0 (1'b1) record(payload);
      if (i == 0) begin
        $assertkill;
        $asserton;
        payload = 5;
      end
    end
  end

  function void record(input int value);
    deferred_sum += value;
  endfunction

  always #2 clk = ~clk;
  always @(posedge clk) cyc <= cyc + 1;

  assert property (@(posedge clk) (cyc == 2 || cyc == 5) |-> ##2 1'b0)
  else failures++;
  assert property (@(posedge clk) go |-> ##2 1'b1) split_passes++;
  assert property (@(posedge clk) (go ##1 go) |-> ##2 1'b1) unsplit_passes++;
  assert property (@(posedge clk) (cyc == 2) |-> ##2 1'b1) late_split++;
  assert property (@(posedge clk) ((cyc == 1) ##1 (cyc == 2)) |-> ##2 1'b1) late_unsplit++;

  always @(negedge clk) begin
    case (cyc)
      3: begin
        // Global Kill retains pending reports in both configurations.
        `checkd(deferred_sum, 8);
        `checkd(split_passes > 0, 1);
        `checkd(unsplit_passes > 0, 1);
        split_at_off = split_passes;
        unsplit_at_off = unsplit_passes;
        late_split_at_off = late_split;
        late_unsplit_at_off = late_unsplit;
        $assertoff;
      end
      6, 9: begin
        // Both configurations suppress NFA actions at completion while Off.
        `checkd(failures, 0);
        `checkd(split_passes, split_at_off);
        `checkd(unsplit_passes, unsplit_at_off);
        `checkd(late_split, late_split_at_off);
        `checkd(late_unsplit, late_unsplit_at_off);
        if (cyc == 9) begin
          $display("*-* All Finished *-*");
          $finish;
        end
      end
      default: begin
      end
    endcase
  end
endmodule
