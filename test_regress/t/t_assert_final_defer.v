// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define checks(gotv,expv) do if ((gotv) != (expv)) begin $write("%%Error: %s:%0d:  got='%s' exp='%s'\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// The action of a final deferred assertion runs in the Postponed region, with its arguments
// as when the assertion was evaluated, and only for the last evaluation of its process in a
// time step (IEEE 1800-2023 16.4.1)
module t;
  int state;
  int seen_state;
  int seen_arg;
  int reports;
  function automatic void show(int arg);
    seen_state = state;
    seen_arg = arg;
    ++reports;
  endfunction

  logic g = 0;
  int glitch_reports;
  function automatic void glitch();
    ++glitch_reports;
  endfunction
  always_comb assert final (!g) else glitch();

  string text;

  initial begin
    // Test: the action runs after the process has moved on, with the argument value when made
    #1;
    state = 1;
    assert final (1) show(state);
    state = 2;
    `checkd(reports, 0);
    #1;
    `checkd(reports, 1);
    `checkd(seen_state, 2);
    `checkd(seen_arg, 1);
    // Test: a failure that a later evaluation in the time step clears is not reported
    g = 1;
    g = 0;
    #1;
    `checkd(glitch_reports, 0);
    g = 1;
    #1;
    `checkd(glitch_reports, 1);
    // Test: %m names the assertion
    begin : blk
      labeled : assert final (1) $sformat(text, "%m");
    end
    #1;
    `checks(text, "t.blk.labeled");
    $write("*-* All Finished *-*\n");
    $finish;
  end

  // Test: in a final procedure, after which no Postponed region runs, the action is not lost
  int final_reports;
  function automatic void final_report();
    ++final_reports;
  endfunction
  final begin
    assert final (0)
    else final_report();
    `checkd(final_reports, 1);
  end
endmodule
