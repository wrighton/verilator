// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// A disable of the outermost scope of a procedure forking processes drops its pending deferred
// assertion reports (IEEE 1800-2023 16.4.4), and the processes it forked run
module t (
    input clk
);
  int cyc = 0;
  always @(posedge clk) cyc <= cyc + 1;

  int fail_n = 0, child_n = 0;
  function automatic void reportFail();
    ++fail_n;
  endfunction
  always @(posedge clk) begin : forker
    fork
      ++child_n;
    join_none
    assert #0 (cyc != 3)
    else reportFail();
  end
  always @(posedge clk) if (cyc == 3) #0 disable forker;

  always @(negedge clk) begin
    `checkd(child_n, cyc);
    if (cyc == 6) begin
      `checkd(fail_n, 0);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
