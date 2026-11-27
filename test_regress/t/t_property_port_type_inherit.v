// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// A checker port without a type has the type and direction of the previous port
checker chk (byte a, b, input bit ck, output int sum, last);
  always @(posedge ck) begin
    sum <= int'(a) + int'(b);
    last <= int'(b);
  end
endchecker

// A port after untyped, or after var without a data type, is not of the type before
checker chk_clear (byte a, untyped b, c, var byte d, e, var f, g, input bit ck,
                   output int n_clear);
  always @(posedge ck) if (a < 0 && b > 0 && c > 0 && d < 0 && e < 0 && f > 0 && g > 0) n_clear++;
endchecker

module t (
    input clk
);
  int cyc = 0;
  logic [7:0] ff = 8'hff;

  // A port without a type has the type of the previous port, so b is a byte and its
  // actual 8'hff is cast to -1 (IEEE 1800-2023 16.8, 16.12)
  property p_inherit(byte a, b);
    @(posedge clk) a < 0 && b < 0;
  endproperty
  sequence s_inherit(byte a, b);
    a < 0 && b < 0;
  endsequence
  // A port after untyped is untyped, so c keeps the actual's unsigned value
  property p_untyped(byte a, untyped b, c);
    @(posedge clk) a < 0 && b > 0 && c > 0;
  endproperty
  // So after var without a data type
  property p_var(byte a, var b, c);
    @(posedge clk) a < 0 && b > 0 && c > 0;
  endproperty
  // A first port without a type is untyped
  property p_first(x, byte y, z);
    @(posedge clk) x > 0 && y < 0 && z < 0;
  endproperty

  int n_inherit = 0, n_named = 0, n_seq = 0, n_seq_named = 0;
  int n_untyped = 0, n_var = 0, n_first = 0, n_first_named = 0, n_clear = 0;
  int sum, last, sum_named, last_named;
  assert property (p_inherit(ff, ff)) n_inherit++;
  assert property (p_inherit(.b(ff), .a(ff))) n_named++;
  assert property (@(posedge clk) s_inherit(ff, ff)) n_seq++;
  assert property (@(posedge clk) s_inherit(.b(ff), .a(ff))) n_seq_named++;
  assert property (p_untyped(ff, ff, ff)) n_untyped++;
  assert property (p_var(ff, ff, ff)) n_var++;
  assert property (p_first(ff, ff, ff)) n_first++;
  assert property (p_first(.z(ff), .x(ff), .y(ff))) n_first_named++;
  chk check (ff, ff, clk, sum, last);
  chk check_named (.last(last_named), .sum(sum_named), .ck(clk), .b(ff), .a(ff));
  // verilator lint_off WIDTHTRUNC
  chk_clear check_clear (ff, ff, ff, ff, ff, ff, ff, clk, n_clear);
  // verilator lint_on WIDTHTRUNC

  always @(posedge clk) begin
    cyc <= cyc + 1;
    if (cyc == 10) begin
      `checkd(n_inherit, 10);
      `checkd(n_named, 10);
      `checkd(n_seq, 10);
      `checkd(n_seq_named, 10);
      `checkd(n_untyped, 10);
      `checkd(n_var, 10);
      `checkd(n_first, 10);
      `checkd(n_first_named, 10);
      `checkd(sum, -2);
      `checkd(last, -1);
      `checkd(sum_named, -2);
      `checkd(last_named, -1);
      `checkd(n_clear, 10);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
