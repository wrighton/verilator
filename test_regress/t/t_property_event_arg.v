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
  bit clk = 0;
  always #5 clk = ~clk;
  int cyc = 0;
  always @(posedge clk) cyc <= cyc + 1;
  wire en = cyc[0];

  // Clocking events counted directly
  int n_pos = 0;
  int n_neg = 0;
  int n_both = 0;
  int n_iff = 0;
  always @(posedge clk) n_pos++;
  always @(negedge clk) n_neg++;
  always @(edge clk) n_both++;
  always @(posedge clk iff en) n_iff++;

  // An event expression is the actual of an untyped formal or a formal of type event
  property p_untyped(clk_ev, x);
    @clk_ev x;
  endproperty
  property p_event(event ev, logic x);
    @(ev) x;
  endproperty
  property p_outer(event ev, logic x);
    p_event(ev, x);
  endproperty
  sequence s_event(event ev, logic x);
    @(ev) x;
  endsequence
  sequence s_untyped(ev, x);
    @(ev) x;
  endsequence

  int a_pos = 0;
  int a_neg = 0;
  int a_both = 0;
  int a_iff = 0;
  int a_named = 0;
  int a_outer = 0;
  int a_seq = 0;
  int a_seq_untyped = 0;
  assert property (p_untyped(posedge clk, cyc >= 0)) a_pos++;
  assert property (p_event(negedge clk, cyc >= 0)) a_neg++;
  assert property (p_event(edge clk, cyc >= 0)) a_both++;
  assert property (p_event(posedge clk iff en, cyc >= 0)) a_iff++;
  assert property (p_event(.x(cyc >= 0), .ev(negedge clk))) a_named++;
  assert property (p_outer(posedge clk, cyc >= 0)) a_outer++;
  assert property (s_event(posedge clk, cyc >= 0)) a_seq++;
  assert property (s_untyped(negedge clk, cyc >= 0)) a_seq_untyped++;

  initial begin
    #203;
    `checkd(n_pos, 20);
    `checkd(n_iff, 10);
    `checkd(a_pos, n_pos);
    `checkd(a_neg, n_neg);
    `checkd(a_both, n_both);
    `checkd(a_iff, n_iff);
    `checkd(a_named, n_neg);
    `checkd(a_outer, n_pos);
    `checkd(a_seq, n_pos);
    `checkd(a_seq_untyped, n_neg);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
