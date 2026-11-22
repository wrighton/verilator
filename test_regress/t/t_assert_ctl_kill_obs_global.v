// DESCRIPTION: Verilator: Global Kill flushes immature observed deferred reports
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__, `__LINE__, (gotv), (expv)); `stop; end while (0);
// verilog_format: on

module t;
  int sum = 0;
  int value = 3;

  task automatic record_report(input int payload);
    sum += payload;
    // The remaining two reports have already matured in Observed.
    if (payload == 5) $assertkill;
  endtask

  initial begin
    for (int i = 0; i < 4; ++i) begin
      report_site :
      assert #0 (1'b1) record_report(value);
      if (i == 0) begin
        $assertkill;
        $asserton;
      end
      value += 2;
    end
    #1;
    `checkd(sum, 21);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
