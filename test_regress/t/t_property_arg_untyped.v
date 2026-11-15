// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

// Selects from, edges of, and operators on untyped property formal arguments,
// typed by the actual arguments (IEEE 1800-2023 16.8, 16.12). Each instance is compared
// with the same assertion written out.

package pkg;
  property prop_bit(v, i);
    v[i];
  endproperty
endpackage

module t (
  input clk
);
  int unsigned crc = 32'h1;
  logic [3:0] req = 0, gnt = 0;
  logic [7:0] wide = 0, wide_gnt = 0;
  logic [1:0] sym = 0;
  // verilator lint_off ASCRANGE
  logic [0:3] rev = 0;
  // verilator lint_on ASCRANGE
  logic [4:1] off = 0;
  logic [2:0] arr[4];
  logic [1:0] x = 0;
  logic [3:0] y = 0;
  int cyc = 0;

  always @(posedge clk) begin
    cyc <= cyc + 1;
    crc <= {crc[30:0], crc[31] ^ crc[21] ^ crc[1] ^ crc[0]};
    req <= crc[3:0];
    gnt <= crc[7:4];
    wide <= crc[15:8];
    wide_gnt <= crc[31:24] ^ crc[7:0];
    sym <= crc[17:16];
    rev <= crc[11:8];
    off <= crc[27:24];
    arr[crc[19:18]] <= crc[22:20];
    x <= crc[1:0];
    y <= crc[7:4];
    if (cyc == 40) $finish;
  end

  property no_req_no_grant(requestors, sym_requestor, grant);
    !requestors[sym_requestor] |-> !grant[sym_requestor];
  endproperty
  property prop_part(v);
    v[2:1] != 2'b11;
  endproperty
  property prop_plus(v, i);
    v[i+:2] != 2'b00;
  endproperty
  property prop_clk(ck, x, y);
    @(posedge ck) x |-> ##1 y;
  endproperty
  property prop_inner(v, i);
    v[i] |-> 1'b1;
  endproperty
  property prop_outer(r, k);
    prop_inner(r, k);
  endproperty
  property prop_arr(a, i);
    a[i] != 3'd0;
  endproperty
  property prop_mix(v, logic [1:0] i);
    v[i] |-> arr[i] != 3'd0;
  endproperty
  property prop_plain(x, y);
    x |-> y;
  endproperty
  property prop_wrap(x, y);
    prop_plain(x, y);
  endproperty
  // Never instanced, so never typed

  property prop_unused(v);
    v[3];
  endproperty

  // Instanced with actual arguments of two widths
  int fails_req = 0, ref_fails_req = 0;
  assert property (@(posedge clk) no_req_no_grant(req, sym, gnt))
  else fails_req++;
  assert property (@(posedge clk) !req[sym] |-> !gnt[sym])
  else ref_fails_req++;
  int fails_wide = 0, ref_fails_wide = 0;
  assert property (@(posedge clk) no_req_no_grant(wide, 3'(cyc), wide_gnt))
  else fails_wide++;
  assert property (@(posedge clk) !wide[3'(cyc)] |-> !wide_gnt[3'(cyc)])
  else ref_fails_wide++;

  // Same types as an earlier instance
  int fails_again = 0, ref_fails_again = 0;
  assert property (@(posedge clk) no_req_no_grant(gnt, sym, req))
  else fails_again++;
  assert property (@(posedge clk) !gnt[sym] |-> !req[sym])
  else ref_fails_again++;

  // Typed and untyped formal arguments, and a property without selects
  int fails_mix = 0, ref_fails_mix = 0;
  assert property (@(posedge clk) prop_mix(req, sym))
  else fails_mix++;
  assert property (@(posedge clk) req[sym] |-> arr[sym] != 3'd0)
  else ref_fails_mix++;
  int fails_wrap = 0, ref_fails_wrap = 0;
  assert property (@(posedge clk) prop_wrap(req[1], gnt[1]))
  else fails_wrap++;
  assert property (@(posedge clk) req[1] |-> gnt[1])
  else ref_fails_wrap++;

  int fails_part = 0, ref_fails_part = 0;
  assert property (@(posedge clk) prop_part(req))
  else fails_part++;
  assert property (@(posedge clk) req[2:1] != 2'b11)
  else ref_fails_part++;

  int fails_plus = 0, ref_fails_plus = 0;
  assert property (@(posedge clk) prop_plus(wide, {1'b0, sym}))
  else fails_plus++;
  assert property (@(posedge clk) wide[{1'b0, sym}+:2] != 2'b00)
  else ref_fails_plus++;

  int fails_clk = 0, ref_fails_clk = 0;
  assert property (prop_clk(clk, req[0], gnt[0]))
  else fails_clk++;
  assert property (@(posedge clk) req[0] |-> ##1 gnt[0])
  else ref_fails_clk++;

  int fails_pkg = 0, ref_fails_pkg = 0;
  assert property (@(posedge clk) pkg::prop_bit(req, sym))
  else fails_pkg++;
  assert property (@(posedge clk) req[sym])
  else ref_fails_pkg++;

  // Same width as req, but other range directions and offsets
  int fails_rev = 0, ref_fails_rev = 0;
  assert property (@(posedge clk) pkg::prop_bit(rev, sym))
  else fails_rev++;
  assert property (@(posedge clk) rev[sym])
  else ref_fails_rev++;
  int fails_off = 0, ref_fails_off = 0;
  assert property (@(posedge clk) pkg::prop_bit(off, 3'(sym) + 3'd1))
  else fails_off++;
  assert property (@(posedge clk) off[3'(sym)+3'd1])
  else ref_fails_off++;

  int fails_outer = 0;
  assert property (@(posedge clk) prop_outer(gnt, sym))
  else fails_outer++;

  int fails_arr = 0, ref_fails_arr = 0;
  assert property (@(posedge clk) prop_arr(arr, sym))
  else fails_arr++;
  assert property (@(posedge clk) arr[sym] != 3'd0)
  else ref_fails_arr++;

  // verilator lint_off WIDTH
  // Untyped formal arguments as operands of operators. Never instanced:
  property p_unused_op(a, b);
    @(posedge clk) (a | b) |-> 1;
  endproperty

  property p_or(a, b);
    (a | b) < 4'h8;
  endproperty
  property p_and(a, b);
    (a & b) |-> b[3];
  endproperty
  property p_xor(a, b);
    (a ^ b) > 4'h7;
  endproperty
  property p_add(a, b);
    a + b > 4'd7;
  endproperty
  property p_shift(a);
    (a << 1) == 2'b10;
  endproperty
  property p_concat(a, b);
    {a, b} < 6'h20;
  endproperty
  property p_repl(a);
    {2{a}} != 4'ha;
  endproperty
  property p_not(a);
    ~a;
  endproperty
  property p_neg(a);
    -a == 2'd3;
  endproperty
  property p_redor(a);
    |a;
  endproperty
  property p_redand(a);
    &a;
  endproperty
  property p_redxor(a);
    ^a;
  endproperty
  property p_countones(a);
    $countones(a) == 2;
  endproperty
  property p_onehot(a);
    $onehot(a);
  endproperty
  property p_countbits(a);
    $countbits(a, 1'b0) == 3;
  endproperty
  property p_signed(a);
    $signed(a) < 0;
  endproperty
  property p_cond(a, b);
    (a ? b : 4'd0) > 4'd8;
  endproperty
  property p_past(a, b);
    $past(a | b) == 4'h7;
  endproperty
  property p_past_each(a, b);
    ($past(a) | $past(b)) < 4'h8;
  endproperty
  property p_stable(a, b);
    $stable(a | b);
  endproperty
  // Operands of logical and sequence operators stay untyped
  property p_logical(a, b);
    !a || (a && b);
  endproperty
  property p_thru(a, b);
    a throughout (b ##1 b);
  endproperty
  property p_inner(a, b);
    (a | b) > 4'h3;
  endproperty
  property p_outer(c, d);
    p_inner(c, d);
  endproperty

`define CHECK_OP(name, inst, expr) \
  int fails_op_``name = 0, ref_fails_op_``name = 0; \
  assert property (@(posedge clk) inst) else fails_op_``name++; \
  assert property (@(posedge clk) expr) else ref_fails_op_``name++;

  `CHECK_OP(or, p_or(x, y), (x | y) < 4'h8)
  `CHECK_OP(and, p_and(x, y), (x & y) |-> y[3])
  `CHECK_OP(xor, p_xor(x, y), (x ^ y) > 4'h7)
  `CHECK_OP(add, p_add(x, y), x + y > 4'd7)
  `CHECK_OP(shift, p_shift(x), (x << 1) == 2'b10)
  `CHECK_OP(concat, p_concat(x, y), {x, y} < 6'h20)
  `CHECK_OP(repl, p_repl(x), {2{x}} != 4'ha)
  `CHECK_OP(not, p_not(x), ~x)
  `CHECK_OP(neg, p_neg(x), -x == 2'd3)
  `CHECK_OP(redor, p_redor(x), |x)
  `CHECK_OP(redand, p_redand(x), &x)
  `CHECK_OP(redxor, p_redxor(y), ^y)
  `CHECK_OP(countones, p_countones(y), $countones(y) == 2)
  `CHECK_OP(onehot, p_onehot(y), $onehot(y))
  `CHECK_OP(countbits, p_countbits(y), $countbits(y, 1'b0) == 3)
  `CHECK_OP(signed, p_signed(x), $signed(x) < 0)
  `CHECK_OP(cond, p_cond(x, y), (x ? y : 4'd0) > 4'd8)
  `CHECK_OP(past, p_past(x, y), $past(x | y) == 4'h7)
  `CHECK_OP(past_each, p_past_each(x, y), ($past(x) | $past(y)) < 4'h8)
  `CHECK_OP(stable, p_stable(x, y), $stable(x | y))
  `CHECK_OP(outer, p_outer(x, y), (x | y) > 4'h3)
  `CHECK_OP(logical, p_logical(x, y), !x || (x && y))
  `CHECK_OP(thru, p_thru(x, y), x throughout (y ##1 y))
  // Same property with actual arguments of other types
  `CHECK_OP(or_wide, p_or(y, x), (y | x) < 4'h8)
  `CHECK_OP(signed_wide, p_signed(y), $signed(y) < 0)
  // verilator lint_on WIDTH

  // Counts read in final (Postponed) to avoid same-timestep races.
  final begin
    `checkd(fails_req, ref_fails_req);
    `checkd(fails_wide, ref_fails_wide);
    `checkd(fails_again, ref_fails_again);
    `checkd(fails_rev, ref_fails_rev);
    `checkd(fails_off, ref_fails_off);
    `checkd(fails_mix, ref_fails_mix);
    `checkd(fails_wrap, ref_fails_wrap);
    `checkd(fails_part, ref_fails_part);
    `checkd(fails_plus, ref_fails_plus);
    `checkd(fails_clk, ref_fails_clk);
    `checkd(fails_pkg, ref_fails_pkg);
    `checkd(fails_outer, 0);
    `checkd(fails_arr, ref_fails_arr);
    `checkd(ref_fails_again, 15);
    `checkd(ref_fails_mix, 15);
    `checkd(ref_fails_wrap, 13);
    `checkd(ref_fails_req, 12);
    `checkd(ref_fails_wide, 8);
    `checkd(ref_fails_part, 11);
    `checkd(ref_fails_plus, 11);
    `checkd(ref_fails_clk, 8);
    `checkd(ref_fails_pkg, 18);
    `checkd(ref_fails_arr, 23);
    `checkd(fails_op_or, ref_fails_op_or);
    `checkd(fails_op_and, ref_fails_op_and);
    `checkd(fails_op_xor, ref_fails_op_xor);
    `checkd(fails_op_add, ref_fails_op_add);
    `checkd(fails_op_shift, ref_fails_op_shift);
    `checkd(fails_op_concat, ref_fails_op_concat);
    `checkd(fails_op_repl, ref_fails_op_repl);
    `checkd(fails_op_not, ref_fails_op_not);
    `checkd(fails_op_neg, ref_fails_op_neg);
    `checkd(fails_op_redor, ref_fails_op_redor);
    `checkd(fails_op_redand, ref_fails_op_redand);
    `checkd(fails_op_redxor, ref_fails_op_redxor);
    `checkd(fails_op_countones, ref_fails_op_countones);
    `checkd(fails_op_onehot, ref_fails_op_onehot);
    `checkd(fails_op_countbits, ref_fails_op_countbits);
    `checkd(fails_op_signed, ref_fails_op_signed);
    `checkd(fails_op_cond, ref_fails_op_cond);
    `checkd(fails_op_past, ref_fails_op_past);
    `checkd(fails_op_past_each, ref_fails_op_past_each);
    `checkd(fails_op_stable, ref_fails_op_stable);
    `checkd(fails_op_outer, ref_fails_op_outer);
    `checkd(fails_op_logical, ref_fails_op_logical);
    `checkd(fails_op_thru, ref_fails_op_thru);
    `checkd(fails_op_or_wide, ref_fails_op_or_wide);
    `checkd(fails_op_signed_wide, ref_fails_op_signed_wide);
    `checkd(ref_fails_op_or, 19);
    `checkd(ref_fails_op_and, 4);
    `checkd(ref_fails_op_xor, 22);
    `checkd(ref_fails_op_add, 28);
    `checkd(ref_fails_op_shift, 17);
    `checkd(ref_fails_op_concat, 23);
    `checkd(ref_fails_op_repl, 11);
    `checkd(ref_fails_op_not, 12);
    `checkd(ref_fails_op_neg, 29);
    `checkd(ref_fails_op_redor, 6);
    `checkd(ref_fails_op_redand, 29);
    `checkd(ref_fails_op_redxor, 18);
    `checkd(ref_fails_op_countones, 29);
    `checkd(ref_fails_op_onehot, 33);
    `checkd(ref_fails_op_countbits, 33);
    `checkd(ref_fails_op_signed, 18);
    `checkd(ref_fails_op_cond, 25);
    `checkd(ref_fails_op_past, 33);
    `checkd(ref_fails_op_past_each, 18);
    `checkd(ref_fails_op_stable, 37);
    `checkd(ref_fails_op_outer, 11);
    `checkd(ref_fails_op_logical, 4);
    `checkd(ref_fails_op_thru, 13);
    `checkd(ref_fails_op_or_wide, 19);
    `checkd(ref_fails_op_signed_wide, 22);
    $write("*-* All Finished *-*\n");
  end
endmodule
