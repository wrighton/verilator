// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

// An always_comb reading what it writes runs once per change of what else it reads (IEEE
// 1800-2023 9.2.2.2.2). A change of a queue cannot be detected, so this one is not run that way,
// and its self-written counter stays a combinational cycle, reported rather than silently
// counting more runs.
module t;
  int q[$];
  int n = 0;
  function automatic void bump();
    n++;
  endfunction
  // verilator lint_off LATCH
  always_comb if (q.size() > 2) bump();
  // verilator lint_on LATCH

  initial begin
    repeat (4) begin
      #1;
      q.push_back(1);
    end
    // The count if it were run by changes
    `checkd(n, 2);
    $finish;
  end
endmodule
