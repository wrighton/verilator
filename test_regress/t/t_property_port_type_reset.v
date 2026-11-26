// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// A typed port of a checker, then an untyped property port in its body
checker chk_p (bit en, bit ck, output int passes);
  property p_untyped(ev);
    @(posedge ck) ev;
  endproperty
  assert property (p_untyped(en)) passes++;
endchecker

// A typed port of a checker, then an untyped sequence port in its body
checker chk_s (bit en, bit ck, output int passes);
  sequence s_untyped(ev);
    ev ##0 1'b1;
  endsequence
  assert property (@(posedge ck) s_untyped(en)) passes++;
endchecker

module t (
    input clk
);
  int cyc = 0;
  bit a = 1'b1;

  // A typed sequence port, then untyped property and sequence ports
  sequence s_typed(bit ev);
    ev ##0 1'b1;
  endsequence
  property p_untyped(ev, x);
    @(posedge clk) ev |-> x;
  endproperty
  sequence s_untyped(ev);
    ev ##0 1'b1;
  endsequence

  // A typed property port, then untyped sequence and property ports
  property p_typed(bit ev);
    @(posedge clk) ev;
  endproperty
  sequence s_untyped2(ev);
    ev ##0 1'b1;
  endsequence
  property p_untyped2(ev);
    @(posedge clk) ev;
  endproperty

  int n_p_untyped = 0, n_s = 0, n_p_typed = 0, n_s2 = 0, n_p_untyped2 = 0, n_chk = 0, n_chk_seq = 0;
  assert property (p_untyped(a, a)) n_p_untyped++;
  assert property (@(posedge clk) s_typed(a) ##0 s_untyped(a)) n_s++;
  assert property (p_typed(a)) n_p_typed++;
  assert property (@(posedge clk) s_untyped2(a)) n_s2++;
  assert property (p_untyped2(a)) n_p_untyped2++;
  chk_p check_p (a, clk, n_chk);
  chk_s check_s (a, clk, n_chk_seq);

  always @(posedge clk) begin
    cyc <= cyc + 1;
    if (cyc == 10) begin
      `checkd(n_p_untyped, 10);
      `checkd(n_s, 10);
      `checkd(n_p_typed, 10);
      `checkd(n_s2, 10);
      `checkd(n_p_untyped2, 10);
      `checkd(n_chk, 10);
      `checkd(n_chk_seq, 10);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
