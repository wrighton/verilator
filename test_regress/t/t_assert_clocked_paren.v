// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

// IEEE 1800-2023 16.12: property_expr ::= ( property_expr ) | clocking_event property_expr
// IEEE 1800-2023 16.7: sequence_expr ::= ( sequence_expr ) | clocking_event sequence_expr
// Each parenthesized clocked form must count the same as its unparenthesized reference.

module t (
  input clk
);
  int unsigned crc = 32'h1;
  bit a, b, rst;
  int cyc = 0;

  always @(posedge clk) begin
    cyc <= cyc + 1;
    crc <= {crc[30:0], crc[31] ^ crc[21] ^ crc[1] ^ crc[0]};
    a <= crc[0];
    b <= crc[1];
    rst <= crc[2] & crc[3];
    if (cyc == 40) $finish;
  end

  // Reference forms without parentheses
  int fails_impl = 0;
  int fails_dis = 0;
  int fails_seq = 0;
  int covers_seq = 0;
  assert property (@(posedge clk) a |-> b) else fails_impl = fails_impl + 1;
  assert property (disable iff (rst) @(posedge clk) a |-> b) else fails_dis = fails_dis + 1;
  assert property (@(posedge clk) a ##1 b) else fails_seq = fails_seq + 1;
  cover property (@(posedge clk) a ##1 b) covers_seq = covers_seq + 1;
  int fails_not = 0;
  int covers_cseq = 0;
  assert property (@(posedge clk) not (a ##1 b)) else fails_not = fails_not + 1;
  cover sequence (@(posedge clk) a ##1 b) covers_cseq = covers_cseq + 1;

  // Clocking event without parentheses around its expression
  int fails_any = 0;
  int fails_direct_any = 0;
  int covers_any = 0;
  int covers_direct_any = 0;
  assert property (@clk a |-> b) else fails_any = fails_any + 1;
  cover sequence (@clk a ##1 b) covers_any = covers_any + 1;
  // verilog_format: off
  assert property ((@clk a |-> b)) else fails_direct_any = fails_direct_any + 1;
  cover sequence ((@clk a ##1 b)) covers_direct_any = covers_direct_any + 1;
  // verilog_format: on

  // Clocked property_expr in parentheses as a named property body
  int fails_named = 0;
  // verilog_format: off  // verible does not support a parenthesized clocking event
  property p_paren;
    (@(posedge clk) a |-> b);
  endproperty
  // verilog_format: on
  assert property (p_paren) else fails_named = fails_named + 1;

  // Directly in the assertion, and in nested parentheses
  int fails_direct = 0;
  int fails_nested = 0;
  // verilog_format: off
  assert property ((@(posedge clk) a |-> b)) else fails_direct = fails_direct + 1;
  assert property (((@(posedge clk) a |-> b))) else fails_nested = fails_nested + 1;
  // verilog_format: on

  // After disable iff
  int fails_named_dis = 0;
  // verilog_format: off
  property p_paren_dis;
    disable iff (rst) (@(posedge clk) a |-> b);
  endproperty
  // verilog_format: on
  assert property (p_paren_dis) else fails_named_dis = fails_named_dis + 1;

  // Clocked sequence_expr in parentheses, as a sequence body and directly
  int fails_named_seq = 0;
  int fails_direct_seq = 0;
  // verilog_format: off
  sequence s_paren;
    (@(posedge clk) a ##1 b);
  endsequence
  assert property (s_paren) else fails_named_seq = fails_named_seq + 1;
  assert property ((@(posedge clk) a ##1 b)) else fails_direct_seq = fails_direct_seq + 1;
  // verilog_format: on

  // With a property operator
  int fails_direct_not = 0;
  // verilog_format: off
  assert property ((@(posedge clk) not (a ##1 b))) else fails_direct_not = fails_direct_not + 1;
  // verilog_format: on

  // In a cover property and a cover sequence
  int covers_direct_seq = 0;
  int covers_direct_cseq = 0;
  // verilog_format: off
  cover property ((@(posedge clk) a ##1 b)) covers_direct_seq = covers_direct_seq + 1;
  cover sequence ((@(posedge clk) a ##1 b)) covers_direct_cseq = covers_direct_cseq + 1;
  // verilog_format: on

  // Counts read in final (Postponed) to avoid same-timestep races.
  final begin
    `checkd(fails_impl, 12);
    `checkd(fails_dis, 5);
    `checkd(fails_seq, 17);
    `checkd(covers_seq, 23);
    `checkd(fails_not, 23);
    `checkd(covers_cseq, 23);
    `checkd(fails_any, 24);
    `checkd(covers_any, 35);
    `checkd(fails_named, fails_impl);
    `checkd(fails_direct, fails_impl);
    `checkd(fails_nested, fails_impl);
    `checkd(fails_named_dis, fails_dis);
    `checkd(fails_named_seq, fails_seq);
    `checkd(fails_direct_seq, fails_seq);
    `checkd(covers_direct_seq, covers_seq);
    `checkd(fails_direct_not, fails_not);
    `checkd(covers_direct_cseq, covers_cseq);
    `checkd(fails_direct_any, fails_any);
    `checkd(covers_direct_any, covers_any);
    $write("*-* All Finished *-*\n");
  end
endmodule
