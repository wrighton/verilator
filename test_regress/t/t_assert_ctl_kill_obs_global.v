// DESCRIPTION: Verilator: Global Kill flushes immature observed deferred reports
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while (0);
// verilog_format: on

module t;
  int sum = 0;
  int count = 0;
  int stale_count = 0;
  int value = 1;

  task automatic record_report(input int payload);
    sum += payload;
    // Every report still waiting for delivery has already matured in Observed.
    if (payload == 5) $assertkill;
  endtask

  task automatic record_count();
    count++;
  endtask

  task automatic record_stale();
    stale_count++;
  endtask

  initial begin
    for (int i = 0; i < 5; ++i) begin
      assert #0 (1'b1) record_report(value);
      assert #0 (1'b1) record_count();
      if (i < 2) begin
        // No executions of this site will queue reports after Kill.
        assert #0 (1'b1) record_stale();
      end
      if (i == 1) begin
        $assertkill;
        $asserton;
      end
      value += 2;
    end
    #1;
    `checkd(sum, 21);
    `checkd(count, 3);
    `checkd(stale_count, 0);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
