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
  int cnt = 0;
  task automatic inc;
    cnt++;
  endtask
  initial begin
    // Disables of targets that cannot be executing need no std::process
    inc();
    disable inc;
    begin : blk
      cnt++;
    end
    disable blk;
    `checkd(cnt, 2);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
