// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// A subroutine call match item in the antecedent of an implication runs once for each attempt
// whose antecedent matches (IEEE 1800-2023 16.11), reading the local variables assigned before it

module t;
  bit clk = 0;
  initial forever #1 clk = ~clk;
  int cyc = 0;
  bit a = 0;
  bit b = 0;
  int x = 0;
  localparam int N = 6;
  int calls[N];
  int pass[N];
  int fail[N];
  int wrong = 0;
  function automatic void rec(int i);
    ++calls[i];
  endfunction
  int rangeCalls = 0;
  function automatic void recRange();
    ++rangeCalls;
  endfunction
  task automatic recv(int i, int value, int expValue);
    ++calls[i];
    if (value != expValue) ++wrong;
  endtask

  /* verilator lint_off SIDEEFFECT */
  property p_local(int i);
    int v;
    (a, v = x, recv(i, v, x)) |-> b;
  endproperty
  property p_local_delay(int i);
    int v;
    (a, v = x, recv(i, v, x)) |-> ##1 b;
  endproperty

  // Test: a void function call, with a boolean consequent
  assert property (@(posedge clk) (a, rec(0)) |-> b) ++pass[0];
  else ++fail[0];
  // Test: a void function call, with a consequent taking a cycle
  assert property (@(posedge clk) (a, rec(1)) |-> ##1 b) ++pass[1];
  else ++fail[1];
  // Test: a task call, non-overlapped
  assert property (@(posedge clk) (a, recv(2, x, x)) |=> b) ++pass[2];
  // Test: a task call reading a local variable, with a boolean consequent
  assert property (@(posedge clk) p_local(3)) ++pass[3];
  else ++fail[3];
  // Test: a task call reading a local variable, with a consequent taking a cycle
  assert property (@(posedge clk) p_local_delay(4))
  else ++fail[4];
  // Test: a call after a range delay, for each match of the antecedent
  assert property (@(posedge clk) (a ##[0:1] (b, recRange())) |-> ##1 b)
  else;
  /* verilator lint_on SIDEEFFECT */
  // The actions without match items
  assert property (@(posedge clk) a |-> b) ++pass[5];
  else ++fail[5];

  int attempts = 0;
  int rangeMatches = 0;
  bit pa = 0;
  always @(posedge clk) begin
    if (a) ++attempts;
    if (a && b) ++rangeMatches;
    if (pa && b) ++rangeMatches;
    pa <= a;
    cyc <= cyc + 1;
    a <= cyc % 2 == 0;
    b <= cyc % 4 != 0;
    x <= cyc;
  end

  always @(negedge clk) begin
    if (cyc == 40) begin
      for (int i = 0; i < 5; ++i) `checkd(calls[i], attempts);
      `checkd(wrong, 0);
      `checkd(rangeCalls, rangeMatches);
      `checkd(pass[0], pass[5]);
      `checkd(fail[0], fail[5]);
      `checkd(pass[3], pass[5]);
      `checkd(fail[3], fail[5]);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
