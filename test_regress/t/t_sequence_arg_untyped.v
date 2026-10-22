// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

// Untyped formal arguments of a sequence take the type of the actual argument
// (IEEE 1800-2023 16.8)
module t (
  input clk
);
  int cyc = 0;
  logic [7:0] len = 0;
  logic [32:0] wide = 0;
  logic [6:0] d7 = 0, e7 = 0;
  bit signed [4:0] sa = 0;
  bit [4:0] ub = 0;

  always @(posedge clk) begin
    cyc <= cyc + 1;
    len <= len + 8'd3;
    wide <= {wide[31:0], 1'b1};
    d7 <= d7 + 7'd37;
    e7 <= (cyc % 3 == 0) ? d7 + 7'd38 : d7 + 7'd5;
    sa <= sa + 5'sd7;
    ub <= ub + 5'd3;
    if (cyc == 20) $finish;
  end

  sequence seq_eq(x, y);
    x == y;
  endsequence
  // A typed sequence port does not make the formals of a later property typed
  sequence seq_typed(logic x);
    x == 1'b1;
  endsequence
  property prop_untyped(x, y);
    seq_eq(x, y);
  endproperty

  // A sequence instance as the actual argument of an untyped formal
  sequence seq_ab;
    len[1] ##1 len[2];
  endsequence
  sequence seq_a;
    len[0] == 1'b1;
  endsequence
  sequence seq_then(q);
    q ##1 len[3];
  endsequence
  // Seven-bit and explicitly untyped formals
  sequence seq_plus(din, testv);
    (din != 0) ##2 (testv == din + 7'd1);
  endsequence
  sequence seq_keyword(untyped din, untyped testv);
    ##1 (testv == din);
  endsequence
  // A formal after a typed one has its type, here signed
  sequence seq_inherit(bit signed [4:0] lhs, rhs);
    rhs < lhs;
  endsequence
  // A sequence with local variables leaves the formals of a later property untyped, and
  // the ports of a later function implicitly typed
  sequence seq_local(bit [6:0] x, y);
    bit [6:0] v;
    (1, v = x) ##1 (y == v + 7'd5);
  endsequence
  property prop_after_local(x, y);
    seq_eq(x, y);
  endproperty
  function automatic logic implicit_arg(input a);
    return a;
  endfunction
  // An untyped formal as a cycle delay bound
  sequence seq_window(n);
    len[1] ##[1:n] len[3];
  endsequence

  int fails_len = 0, ref_fails_len = 0;
  assert property (@(posedge clk) seq_eq(len, 8'd9))
  else fails_len++;
  assert property (@(posedge clk) len == 8'd9)
  else ref_fails_len++;

  int fails_wide = 0, ref_fails_wide = 0;
  assert property (@(posedge clk) prop_untyped(wide, 33'h1_0000_0003))
  else fails_wide++;
  assert property (@(posedge clk) wide == 33'h1_0000_0003)
  else ref_fails_wide++;

  int fails_multi = 0, ref_fails_multi = 0;
  assert property (@(posedge clk) seq_then(seq_ab))
  else fails_multi++;
  assert property (@(posedge clk) len[1] ##1 len[2] ##1 len[3])
  else ref_fails_multi++;

  int fails_single = 0, ref_fails_single = 0;
  assert property (@(posedge clk) seq_then(seq_a))
  else fails_single++;
  assert property (@(posedge clk) len[0] ##1 len[3])
  else ref_fails_single++;

  int fails_window = 0, ref_fails_window = 0;
  assert property (@(posedge clk) seq_window(5))
  else fails_window++;
  assert property (@(posedge clk) len[1] ##[1:5] len[3])
  else ref_fails_window++;

  int fails_plus = 0, ref_fails_plus = 0;
  assert property (@(posedge clk) seq_plus(d7, e7))
  else fails_plus++;
  assert property (@(posedge clk) (d7 != 0) ##2 (e7 == d7 + 7'd1))
  else ref_fails_plus++;

  int fails_keyword = 0, ref_fails_keyword = 0;
  assert property (@(posedge clk) seq_keyword(d7, e7))
  else fails_keyword++;
  assert property (@(posedge clk) ##1 (e7 == d7))
  else ref_fails_keyword++;

  int fails_inherit = 0, ref_fails_inherit = 0;
  assert property (@(posedge clk) seq_inherit(sa, ub))
  else fails_inherit++;
  assert property (@(posedge clk) $signed(ub) < sa)
  else ref_fails_inherit++;

  int fails_local = 0, ref_fails_local = 0;
  assert property (@(posedge clk) seq_local(d7, e7))
  else fails_local++;
  assert property (@(posedge clk) 1 ##1 (e7 == $past(d7) + 7'd5))
  else ref_fails_local++;

  int fails_after_local = 0, fails_implicit = 0;
  assert property (@(posedge clk) prop_after_local(len, 8'd9))
  else fails_after_local++;
  assert property (@(posedge clk) implicit_arg(len[0]) == len[0])
  else fails_implicit++;

  int fails_typed = 0;
  assert property (@(posedge clk) seq_typed(cyc < 100))
  else fails_typed++;

  // Counts read in final (Postponed) to avoid same-timestep races.
  final begin
    `checkd(fails_len, ref_fails_len);
    `checkd(fails_len, 20);
    `checkd(fails_wide, ref_fails_wide);
    `checkd(fails_wide, 21);
    `checkd(fails_multi, ref_fails_multi);
    `checkd(fails_multi, 16);
    `checkd(fails_single, ref_fails_single);
    `checkd(fails_single, 11);
    `checkd(fails_window, ref_fails_window);
    `checkd(fails_window, 11);
    `checkd(fails_plus, ref_fails_plus);
    `checkd(fails_plus, 13);
    `checkd(fails_keyword, ref_fails_keyword);
    `checkd(fails_keyword, 20);
    `checkd(fails_inherit, ref_fails_inherit);
    `checkd(fails_inherit, 11);
    `checkd(fails_local, ref_fails_local);
    `checkd(fails_local, 7);
    `checkd(fails_after_local, fails_len);
    `checkd(fails_implicit, 0);
    `checkd(fails_typed, 0);
    $write("*-* All Finished *-*\n");
  end
endmodule
