// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// An NBA executed at time 0, after timing controls that do not suspend the process, is committed
// at time 0
package p;
  event e;
  task automatic rec(int k, bit doWait);
    if (doWait) @e;
    if (k > 0) rec(k - 1, doWait);
  endtask
  task automatic nonrec(bit doWait);
    if (doWait) @e;
  endtask
endpackage

class Cls;
  event e;
  task rec(int k, bit doWait);
    if (doWait) @e;
    if (k > 0) rec(k - 1, doWait);
  endtask
endclass

module t;
  bit never;
  initial never = $test$plusargs("never");

  // Recursive package task, await not taken
  int x1;
  initial begin
    p::rec(2, never);
    x1 <= 11;
    #1 `checkd(x1, 11);
  end

  // Non-recursive package task, await not taken
  int x2;
  initial begin
    p::nonrec(never);
    x2 <= 12;
    #1 `checkd(x2, 12);
  end

  // Class method, await not taken
  int x3;
  initial begin
    Cls c;
    c = new;
    c.rec(2, never);
    x3 <= 13;
    #1 `checkd(x3, 13);
  end

  // Conditional await directly in the process, not taken
  int x4;
  initial begin
    if (never) @p::e;
    x4 <= 14;
    #1 `checkd(x4, 14);
  end

  // Wait on a condition that is already true
  int x5;
  initial begin
    wait (!never);
    x5 <= 15;
    #1 `checkd(x5, 15);
  end

  // NBA to an array element and to a struct member
  int arr[3:1];
  struct {
    int a;
    int b;
  } st;
  initial begin
    p::rec(1, never);
    arr[2] <= 16;
    st.b <= 17;
    #1;
    `checkd(arr[2], 16);
    `checkd(st.b, 17);
  end

  // Await taken: committed after the process resumes
  int x7;
  Cls ct = new;
  initial begin
    p::rec(0, !never);
    x7 <= 19;
    #1 `checkd(x7, 19);
  end
  initial begin
    ct.rec(0, !never);
    x7 <= 20;
    #1 `checkd(x7, 20);
  end
  initial begin
    #2 `checkd(x7, 0);
    ->p::e;
    #2 `checkd(x7, 19);
    ->ct.e;
    #2 `checkd(x7, 20);
  end

  // Always process, first iteration does not suspend before the NBA
  int x8;
  event e8;
  always begin
    p::rec(1, never);
    x8 <= x8 + 1;
    @e8;
  end
  initial begin
    #1 `checkd(x8, 1);
    ->e8;
    #1 `checkd(x8, 2);
  end

  // Nonblocking event trigger
  event e9;
  int x9;
  always @e9 x9 = 21;
  initial begin
    p::rec(1, never);
    ->>e9;
    #1 `checkd(x9, 21);
  end

  initial begin
    #10;
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
