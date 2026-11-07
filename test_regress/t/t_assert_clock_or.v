// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

// Assertion clocking events with 'or' and ',' (IEEE 1800-2023 16.12, 14.3, 9.4.2)
module t (
  input clk
);
  int unsigned crc = 32'h1;
  bit a, b;
  int cyc = 0;

  always @(posedge clk) begin
    cyc <= cyc + 1;
    crc <= {crc[30:0], crc[31] ^ crc[21] ^ crc[1] ^ crc[0]};
    a <= crc[0];
    b <= crc[1];
    if (cyc == 40) $finish;
  end

  // Reference model, evaluated on both clock edges
  int edges = 0;
  int exp_fails_a = 0;
  int exp_fails_b_en = 0;
  int exp_fails_impl = 0;
  bit prev_a = 0;
  always @(posedge clk or negedge clk) begin
    ++edges;
    if (!a) ++exp_fails_a;
    if (cyc >= 3 && !b) ++exp_fails_b_en;
    if (prev_a && !b) ++exp_fails_impl;
    prev_a = a;
  end

  property p_or(x);
    @(posedge clk or negedge clk) x;
  endproperty

  // verilog_format: off  // verible does not support clocking events inside sequence declarations
  sequence s_or;
    @(posedge clk or negedge clk) a;
  endsequence
  // verilog_format: on

  int passes_or = 0, fails_or = 0;
  assert property (@(posedge clk or negedge clk) a) passes_or++;
  else fails_or++;

  int fails_comma = 0;
  assert property (@(posedge clk, negedge clk) disable iff (cyc < 3) b)
  else fails_comma++;

  int fails_dis_first = 0;
  assert property (disable iff (cyc < 3) @(posedge clk or negedge clk) b)
  else fails_dis_first++;

  int fails_impl = 0;
  assert property (@(posedge clk or negedge clk) a |-> ##1 b)
  else fails_impl++;

  int fails_decl = 0;
  assert property (p_or(a))
  else fails_decl++;

  int fails_seq = 0;
  assert property (s_or)
  else fails_seq++;

  property p_plain(x);
    x;
  endproperty

  int fails_outer = 0;
  assert property (@(posedge clk or negedge clk) p_plain(a))
  else fails_outer++;

  property p_outer(x);
    @(posedge clk or negedge clk) p_plain(x);
  endproperty

  int fails_nested = 0;
  assert property (p_outer(a))
  else fails_nested++;

  // Repetitions, each also clocked by the equivalent single 'edge' event
  int fails_goto_or = 0, fails_goto_edge = 0;
  assert property (@(posedge clk or negedge clk) a [-> 2] |=> b)
  else fails_goto_or++;
  assert property (@(edge clk) a [-> 2] |=> b)
  else fails_goto_edge++;

  int fails_noncons_or = 0, fails_noncons_edge = 0;
  assert property (@(posedge clk or negedge clk) a [= 2] |=> b)
  else fails_noncons_or++;
  assert property (@(edge clk) a [= 2] |=> b)
  else fails_noncons_edge++;

  // A weak repetition does not fail here, so count its passes
  int passes_rep_or = 0, passes_rep_edge = 0;
  assert property (@(posedge clk or negedge clk) b [= 2]) passes_rep_or++;
  assert property (@(edge clk) b [= 2]) passes_rep_edge++;

  // Three-item 'or' list of edges of a reset and of a compound expression, with
  // disable iff. x and y hold while rst_n rises, so that event is from rst_n alone;
  // the body changes only on negedge clk, away from the events.
  bit rst_n = 0, x = 0, y = 0, d = 0;
  always @(posedge clk) begin
    rst_n <= !(cyc inside {[0:3], [20:23]});
    if (cyc != 4 && cyc != 24) {x, y} <= crc[3:2];
  end
  always @(negedge clk) d <= crc[5];

  int events_xor = 0, enabled_xor = 0, exp_fails_xor = 0;
  always @(posedge rst_n or posedge (x | (y & ~(|x))) or negedge (x | (y & ~(|x)))) begin
    ++events_xor;
    if (rst_n) begin
      ++enabled_xor;
      if (!d) ++exp_fails_xor;
    end
  end

  int passes_xor = 0, fails_xor = 0;
  assert property (@(posedge rst_n or posedge (x | (y & ~(|x))) or negedge (x | (y & ~(|x))))
                   disable iff (!rst_n) d) passes_xor++;
  else fails_xor++;

  sub_dflt u_dflt (.clk, .a, .b);

  // Counts read in final (Postponed) to avoid same-timestep races.
  final begin
    `checkd(edges, 81);
    `checkd(passes_or + fails_or, edges);
    `checkd(fails_or, exp_fails_a);
    `checkd(fails_comma, exp_fails_b_en);
    `checkd(fails_dis_first, exp_fails_b_en);
    `checkd(fails_impl, exp_fails_impl);
    `checkd(fails_decl, exp_fails_a);
    `checkd(fails_seq, exp_fails_a);
    `checkd(fails_outer, exp_fails_a);
    `checkd(fails_nested, exp_fails_a);
    `checkd(fails_goto_edge, 11);
    `checkd(fails_goto_or, fails_goto_edge);
    `checkd(fails_noncons_edge, 46);
    `checkd(fails_noncons_or, fails_noncons_edge);
    `checkd(passes_rep_edge, 79);
    `checkd(passes_rep_or, passes_rep_edge);
    `checkd(events_xor, 9);
    `checkd(enabled_xor, 8);
    `checkd(exp_fails_xor, 5);
    `checkd(passes_xor + fails_xor, enabled_xor);
    `checkd(fails_xor, exp_fails_xor);
    `checkd(u_dflt.edges, 81);
    `checkd(u_dflt.fails, u_dflt.exp_fails);
    $write("*-* All Finished *-*\n");
  end
endmodule

// Default clocking with an 'or' list, inherited by an unclocked assertion
module sub_dflt (
  input clk,
  input bit a,
  input bit b
);
  default clocking @(posedge clk or negedge clk);
  endclocking

  int edges = 0;
  int exp_fails = 0;
  bit prev_a = 0;
  always @(posedge clk or negedge clk) begin
    ++edges;
    if (prev_a && !b) ++exp_fails;
    prev_a = a;
  end

  int fails = 0;
  assert property (a |-> ##1 b)
  else fails++;
endmodule
