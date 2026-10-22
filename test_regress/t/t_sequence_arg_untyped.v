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

  always @(posedge clk) begin
    cyc <= cyc + 1;
    len <= len + 8'd3;
    wide <= {wide[31:0], 1'b1};
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
    `checkd(fails_typed, 0);
    $write("*-* All Finished *-*\n");
  end
endmodule
