// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

// '$' as the actual argument of an untyped property formal used as a cycle delay range maximum
// (IEEE 1800-2023 16.8, 16.12)
module t (
  input clk
);
  int cyc = 0;
  logic a = 0, b = 0;

  always @(posedge clk) begin
    cyc <= cyc + 1;
    a <= (cyc % 8) == 0;
    b <= (cyc % 8) == 5;
    if (cyc == 40) $finish;
  end

  property p_window(r1, r2);
    a |-> ##[r1:r2] b;
  endproperty

  int fail_dollar = 0;
  assert property (@(posedge clk) p_window(1, $))
  else fail_dollar++;

  // A '$' written in the body, not from an actual argument
  property p_literal;
    always [1:$] !(a && b);
  endproperty
  int fail_literal = 0;
  assert property (@(posedge clk) p_literal)
  else fail_literal++;

  // As the maximum of an always or a consecutive repetition range
  property p_always(r);
    a |=> always [0:r] !a;
  endproperty
  property p_rep(r);
    a |=> !b [*1:r] ##1 b;
  endproperty
  int fail_always = 0, fail_always_ref = 0, fail_rep = 0;
  assert property (@(posedge clk) p_always($))
  else fail_always++;
  assert property (@(posedge clk) a |=> always [0:$] !a)
  else fail_always_ref++;
  assert property (@(posedge clk) p_rep($))
  else fail_rep++;

  // In a property typed per instance by another actual argument
  wire [1:0] ab = {b, a};
  property p_sel(r, v);
    v[0] |-> ##[1:r] v[1];
  endproperty
  int fail_sel = 0;
  assert property (@(posedge clk) p_sel($, ab))
  else fail_sel++;

  int fail_named = 0;
  assert property (@(posedge clk) p_window(.r2($), .r1(2)))
  else fail_named++;

  sequence s_a;
    a;
  endsequence
  function automatic logic f_id(logic v);
    return v;
  endfunction
  property p_seq(r);
    s_a ##[1:r] f_id(b);
  endproperty

  int cover_dollar = 0, cover_ref = 0;
  cover property (@(posedge clk) p_seq($)) cover_dollar++;
  cover property (@(posedge clk) a ##[1:$] b) cover_ref++;

  // Likewise for an untyped sequence formal
  sequence s_window(r);
    a ##[1:r] b;
  endsequence
  int cover_seq = 0;
  cover property (@(posedge clk) s_window($)) cover_seq++;

  // b follows a after 5 cycles, so a maximum of 4 fails and does not match
  int fail_finite = 0, cover_finite = 0;
  assert property (@(posedge clk) p_window(1, 4))
  else fail_finite++;
  cover property (@(posedge clk) p_seq(4)) cover_finite++;

  final begin
    `checkd(fail_dollar, 0);
    `checkd(fail_literal, 0);
    `checkd(fail_named, 0);
    `checkd(fail_sel, 0);
    `checkd(fail_always, fail_always_ref);
    `checkd(fail_always, 4);
    `checkd(fail_rep, 0);
    `checkd(fail_finite, 5);
    `checkd(cover_dollar, cover_ref);
    `checkd(cover_dollar, 5);
    `checkd(cover_seq, cover_ref);
    `checkd(cover_finite, 0);
    $write("*-* All Finished *-*\n");
  end
endmodule
