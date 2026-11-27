// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// A subroutine call match item runs once for each attempt reaching it (IEEE 1800-2023 16.11),
// whatever the actions of the assertion

module t;
  bit clk = 0;
  initial forever #1 clk = ~clk;
  int cyc = 0;
  localparam int N = 8;
  int calls[N];
  int p[N];
  int f[N];
  function automatic void rec(int i, int value);
    ++calls[i];
  endfunction
  bit ra = 0;
  bit rb = 0;
  int rangeCalls = 0;
  function automatic void recRange();
    ++rangeCalls;
  endfunction
  int refCount = 0;
  function automatic void recRef(ref int counter);
    ++counter;
  endfunction
  int orCalls = 0;
  function automatic void recOr();
    ++orCalls;
  endfunction
  int firstCalls = 0;
  function automatic void recFirst();
    ++firstCalls;
  endfunction
  int firstConsCalls = 0;
  function automatic void recFirstCons();
    ++firstConsCalls;
  endfunction
  int seqCalls[8];
  function automatic void recSeq(int k);
    ++seqCalls[k];
  endfunction
  int andCalls[5];
  function automatic void recAnd(int k);
    ++andCalls[k];
  endfunction

  /* verilator lint_off SIDEEFFECT */
  property p_rec(int i);
    @(posedge clk) 1 ##1 (1, rec(i, cyc));
  endproperty
  int localCalls = 0;
  int localBad = 0;
  function automatic void recLocal(int value, int expValue);
    ++localCalls;
    if (value != expValue) ++localBad;
  endfunction
  property p_local;
    int v;
    @(posedge clk) (1, v = cyc) ##1 (1, recLocal(v, cyc - 1));
  endproperty
  property p_recb(int i);
    @(posedge clk) (cyc % 3 != 0) ##1 (1, rec(i, 0)) ##1 (cyc % 2 == 0);
  endproperty

  // Test: the item ending the sequence, by the actions of the assertion
  assert property (p_rec(0));
  assert property (p_rec(1))
  else ++f[1];
  assert property (p_rec(2)) ++p[2];
  assert property (p_rec(3)) ++p[3];
  else ++f[3];
  // Test: an item only some attempts reach
  assert property (p_recb(4))
  else;
  assert property (p_recb(5))
  else ++f[5];
  assert property (p_recb(6)) ++p[6];
  else ++f[6];
  assert property (@(posedge clk) not ((cyc % 3 != 0) ##1 (1, rec(7, 0)) ##1 (cyc % 2 == 0)))
    ++p[7];
  else ++f[7];
  // Test: a call reading a local variable gets the value of its attempt
  assert property (p_local);
  // Test: a call with a ref argument
  assert property (@(posedge clk) 1 ##1 (1, recRef(refCount)));
  // Test: an item ending an operand of 'or'
  assert property (@(posedge clk) (1 ##1 (rb, recOr())) or (1 ##2 1));
  // Test: instances of a sequence with an item, each running it
  sequence s_item(int k);
    1 ##1 (rb, recSeq(k));
  endsequence
  sequence s_item7;
    1 ##1 (rb, recSeq(7));
  endsequence
  assert property (@(posedge clk) s_item(1) or s_item(2))
  else;
  assert property (@(posedge clk) s_item(3) and s_item(4))
  else;
  assert property (@(posedge clk) (1 ##1 s_item(5)) or (1 ##1 s_item(6)))
  else;
  assert property (@(posedge clk) s_item7 or s_item7)
  else;
  // Test: an item ending an operand of 'and', the operands ending on the same or other ticks
  assert property (@(posedge clk) (rb, recAnd(1)) and (1 ##2 1))
  else;
  assert property (@(posedge clk) (1 ##1 (rb, recAnd(2))) and (1 ##2 1))
  else;
  assert property (@(posedge clk) (1 ##1 (rb, recAnd(3))) and (1 ##1 1))
  else;
  assert property (@(posedge clk) (1 ##2 1) and (1 ##1 (rb, recAnd(4))))
  else;
  // Test: an item after a range delay, which several attempts reach on one tick
  assert property (@(posedge clk) ra ##[1:3] (rb, recRange()) ##1 1)
  else;
  // Test: an item ending the sequence after a range delay, on the first match of an attempt
  assert property (@(posedge clk) ra ##[0:1] (rb, recFirst()))
  else;
  // Test: the same in a consequent
  assert property (@(posedge clk) cyc % 4 != 1 |-> ra ##[0:1] (rb, recFirstCons()))
  else;
  /* verilator lint_on SIDEEFFECT */

  // Attempts reaching the items, each attempt starting on a clock edge
  int reached = 0;
  int reachedb = 0;
  bit started = 0;
  bit startedb = 0;
  int reachedRb = 0;
  int reachedOr = 0;
  int reachedOr2 = 0;
  bit started2 = 0;
  always @(posedge clk) begin
    if (started) ++reached;
    if (rb) ++reachedRb;
    if (started && rb) ++reachedOr;
    if (started2 && rb) ++reachedOr2;
    started2 <= started;
    if (startedb) ++reachedb;
    started <= 1'b1;
    startedb <= cyc % 3 != 0;
    cyc <= cyc + 1;
    ra <= cyc % 2 == 0 || cyc % 5 == 1;
    rb <= cyc % 3 != 1;
  end
  // Attempts reaching the item after the range delay: those starting 1 to 3 ticks before
  int reachedRange = 0;
  bit [3:1] rangeStarted = '0;
  always @(posedge clk) begin
    if (rb) reachedRange += $countones(rangeStarted);
    rangeStarted = {rangeStarted[2:1], ra};
  end

  // Attempts matching the item after the range delay of 0 to 1 ticks, on their first match
  int reachedFirst = 0;
  int reachedFirstCons = 0;
  bit pendingFirst = 0;
  bit pendingFirstCons = 0;
  always @(posedge clk) begin
    if (ra && rb) ++reachedFirst;
    if (pendingFirst && rb) ++reachedFirst;
    if (cyc % 4 != 1 && ra && rb) ++reachedFirstCons;
    if (pendingFirstCons && rb) ++reachedFirstCons;
    pendingFirst = ra && !rb;
    pendingFirstCons = cyc % 4 != 1 && ra && !rb;
  end

  always @(negedge clk) begin
    if (cyc == 50) begin
      for (int i = 0; i < 4; ++i) `checkd(calls[i], reached);
      for (int i = 4; i < N; ++i) `checkd(calls[i], reachedb);
      `checkd(rangeCalls, reachedRange);
      `checkd(firstCalls, reachedFirst);
      `checkd(firstConsCalls, reachedFirstCons);
      `checkd(refCount, reached);
      `checkd(orCalls, reachedOr);
      for (int k = 1; k <= 4; ++k) `checkd(seqCalls[k], reachedOr);
      `checkd(seqCalls[5], reachedOr2);
      `checkd(seqCalls[6], reachedOr2);
      `checkd(seqCalls[7], 2 * reachedOr);
      `checkd(andCalls[1], reachedRb);
      for (int k = 2; k <= 4; ++k) `checkd(andCalls[k], reachedOr);
      `checkd(localCalls, reached);
      `checkd(localBad, 0);
      `checkd(p[2], reached);
      `checkd(f[1], 0);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
