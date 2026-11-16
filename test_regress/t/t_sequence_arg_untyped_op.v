// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

// Selects from, edges of, and operators on untyped sequence formal arguments,
// typed by the actual arguments (IEEE 1800-2023 16.8). Each instance is compared
// with the same assertion written out.
module t (
  input clk
);
  int unsigned crc = 32'h1;
  logic [1:0] x = 0;
  logic [3:0] y = 0;
  logic [1:0] sym = 0;
  // verilator lint_off ASCRANGE
  logic [0:3] rev = 0;
  // verilator lint_on ASCRANGE
  logic [7:1] off = 0;
  int cyc = 0;

  always @(posedge clk) begin
    cyc <= cyc + 1;
    crc <= {crc[30:0], crc[31] ^ crc[21] ^ crc[1] ^ crc[0]};
    x <= crc[1:0];
    y <= crc[7:4];
    sym <= crc[17:16];
    rev <= crc[11:8];
    off <= crc[27:21];
    if (cyc == 40) $finish;
  end

  // verilator lint_off WIDTH
  // Never instanced
  sequence s_unused(a, b);
    (a | b) ##1 a[0];
  endsequence

  sequence s_bit(v, i);
    v[i];
  endsequence
  sequence s_part(v);
    v[2:1] != 2'b11;
  endsequence
  sequence s_clk(ck, a, b);
    @(posedge ck) a ##1 b;
  endsequence
  sequence s_or(a, b);
    (a | b) < 4'h8;
  endsequence
  sequence s_add(a, b);
    a + b > 4'd7;
  endsequence
  sequence s_concat(a, b);
    {a, b} < 6'h20;
  endsequence
  sequence s_not(a);
    ~a;
  endsequence
  sequence s_redor(a);
    |a;
  endsequence
  sequence s_countones(a);
    $countones(a) == 2;
  endsequence
  sequence s_signed(a);
    $signed(a) < 0;
  endsequence
  sequence s_cond(a, b);
    (a ? b : 4'd0) > 4'd8;
  endsequence
  sequence s_past(a, b);
    $past(a | b) == 4'h7;
  endsequence
  sequence s_stable(a, b);
    $stable(a | b);
  endsequence
  sequence s_delay(a, b);
    (a ^ b) > 4'h3 ##1 b[3];
  endsequence
  // Operands of logical and sequence operators stay untyped
  sequence s_logical(a, b);
    !a || (a && b);
  endsequence
  sequence s_thru(a, b);
    a throughout (b ##1 b);
  endsequence
  sequence s_inner(a, b);
    (a | b) > 4'h3;
  endsequence
  sequence s_outer(c, d);
    s_inner(c, d);
  endsequence
  property p_seq(a, b);
    s_or(a, b) |-> s_redor(b);
  endproperty

`define CHECK_OP(name, inst, expr) \
  int fails_``name = 0, ref_fails_``name = 0; \
  assert property (@(posedge clk) inst) else fails_``name++; \
  assert property (@(posedge clk) expr) else ref_fails_``name++;

  `CHECK_OP(bit, s_bit(y, sym), y[sym])
  `CHECK_OP(part, s_part(y), y[2:1] != 2'b11)
  // Same width as y, or with the same bits selected, but other range directions and offsets
  `CHECK_OP(bit_rev, s_bit(rev, sym), rev[sym])
  `CHECK_OP(part_off, s_part(off), off[2:1] != 2'b11)
  `CHECK_OP(or, s_or(x, y), (x | y) < 4'h8)
  `CHECK_OP(add, s_add(x, y), x + y > 4'd7)
  `CHECK_OP(concat, s_concat(x, y), {x, y} < 6'h20)
  `CHECK_OP(not, s_not(x), ~x)
  `CHECK_OP(redor, s_redor(x), |x)
  `CHECK_OP(countones, s_countones(y), $countones(y) == 2)
  `CHECK_OP(signed, s_signed(x), $signed(x) < 0)
  `CHECK_OP(cond, s_cond(x, y), (x ? y : 4'd0) > 4'd8)
  `CHECK_OP(past, s_past(x, y), $past(x | y) == 4'h7)
  `CHECK_OP(stable, s_stable(x, y), $stable(x | y))
  `CHECK_OP(delay, s_delay(x, y), (x ^ y) > 4'h3 ##1 y[3])
  `CHECK_OP(logical, s_logical(x, y), !x || (x && y))
  `CHECK_OP(thru, s_thru(x, y), x throughout (y ##1 y))
  `CHECK_OP(outer, s_outer(x, y), (x | y) > 4'h3)
  `CHECK_OP(prop, p_seq(x, y), (x | y) < 4'h8 |-> |y)
  // Same sequence with actual arguments of other types
  `CHECK_OP(or_wide, s_or(y, x), (y | x) < 4'h8)
  `CHECK_OP(signed_wide, s_signed(y), $signed(y) < 0)
  // verilator lint_on WIDTH

  int fails_clk = 0, ref_fails_clk = 0;
  assert property (s_clk(clk, x[0], y[0]))
  else fails_clk++;
  assert property (@(posedge clk) x[0] ##1 y[0])
  else ref_fails_clk++;

  // Counts read in final (Postponed) to avoid same-timestep races.
  final begin
    `checkd(fails_bit, ref_fails_bit);
    `checkd(fails_part, ref_fails_part);
    `checkd(fails_bit_rev, ref_fails_bit_rev);
    `checkd(fails_part_off, ref_fails_part_off);
    `checkd(fails_clk, ref_fails_clk);
    `checkd(fails_or, ref_fails_or);
    `checkd(fails_add, ref_fails_add);
    `checkd(fails_concat, ref_fails_concat);
    `checkd(fails_not, ref_fails_not);
    `checkd(fails_redor, ref_fails_redor);
    `checkd(fails_countones, ref_fails_countones);
    `checkd(fails_signed, ref_fails_signed);
    `checkd(fails_cond, ref_fails_cond);
    `checkd(fails_past, ref_fails_past);
    `checkd(fails_stable, ref_fails_stable);
    `checkd(fails_delay, ref_fails_delay);
    `checkd(fails_logical, ref_fails_logical);
    `checkd(fails_thru, ref_fails_thru);
    `checkd(fails_outer, ref_fails_outer);
    `checkd(fails_prop, ref_fails_prop);
    `checkd(fails_or_wide, ref_fails_or_wide);
    `checkd(fails_signed_wide, ref_fails_signed_wide);
    `checkd(ref_fails_bit, 21);
    `checkd(ref_fails_part, 10);
    `checkd(ref_fails_bit_rev, 18);
    `checkd(ref_fails_part_off, 6);
    `checkd(ref_fails_clk, 22);
    `checkd(ref_fails_or, 19);
    `checkd(ref_fails_add, 28);
    `checkd(ref_fails_concat, 23);
    `checkd(ref_fails_not, 12);
    `checkd(ref_fails_redor, 6);
    `checkd(ref_fails_countones, 29);
    `checkd(ref_fails_signed, 18);
    `checkd(ref_fails_cond, 25);
    `checkd(ref_fails_past, 33);
    `checkd(ref_fails_stable, 37);
    `checkd(ref_fails_delay, 19);
    `checkd(ref_fails_logical, 4);
    `checkd(ref_fails_thru, 19);
    `checkd(ref_fails_outer, 11);
    `checkd(ref_fails_prop, 5);
    `checkd(ref_fails_or_wide, 19);
    `checkd(ref_fails_signed_wide, 22);
    $write("*-* All Finished *-*\n");
  end
endmodule
