// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// $assertkill removes the pending reports of observed deferred assertions it kills
// (IEEE 1800-2023 20.11), also when they are turned on again in the same time step, but not
// those that already matured in the Reactive region (IEEE 1800-2023 16.4.1).
module t;
  int calls;
  int values[$];
  function automatic void act(int value);
    ++calls;
    values.push_back(value);
  endfunction
  int kill_calls;
  int kill_sum;
  function automatic void act_kill(int value);
    ++kill_calls;
    kill_sum += value;
    $assertcontrol(5, 4, 1);  // Kill observed deferred assertions
    $assertcontrol(3, 4, 1);
  endfunction

  initial begin
    int v;
    // Test: a report pending at the kill is not made
    #1;
    assert #0 (1) act(1);
    $assertkill;
    $asserton;
    #1;
    `checkd(calls, 0);
    // Test: only the report made after the kill is, with its value at the time it was made
    v = 2;
    assert #0 (1) act(v);
    $assertkill;
    $asserton;
    v = 3;
    assert #0 (1) act(v);
    v = 4;
    #1;
    `checkd(calls, 1);
    `checkd(values[0], 3);
    // Test: a kill of other directive types does not remove an assert report
    assert #0 (1) act(5);
    $assertcontrol(5, 15, 6);  // Kill cover and assume
    $assertcontrol(3, 15, 6);
    #1;
    `checkd(calls, 2);
    `checkd(values[1], 5);
    // Test: a kill of an assume report
    assume #0 (1) act(6);
    $assertcontrol(5, 15, 4);  // Kill assume
    $assertcontrol(3, 15, 4);
    #1;
    `checkd(calls, 2);
    // Test: a kill by a report does not remove the reports that matured with it
    for (int i = 0; i < 2; ++i) begin
      assert #0 (1) act_kill(11 + i);
      assert #0 (1) act(30 + i);
    end
    #1;
    `checkd(kill_calls, 2);
    `checkd(calls, 4);
    `checkd(kill_sum + values[2] + values[3], 84);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
