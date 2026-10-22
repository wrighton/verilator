// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

// IEEE 1800-2023 9.4.2, A.6.5: event_expression ::= ... | ( event_expression )
module t;
  logic a = 0;
  logic b = 0;
  logic en = 0;

  // Each parenthesized form is counted against the same event_expression without parentheses
  int n_edges = 0;
  int n_edges_exp = 0;
  always @((posedge a) or (negedge b)) ++n_edges;
  always @(posedge a or negedge b) ++n_edges_exp;

  int n_or = 0;
  int n_or_exp = 0;
  always @((posedge a or b)) ++n_or;
  always @(posedge a or b) ++n_or_exp;

  int n_comma = 0;
  int n_comma_exp = 0;
  always @(((a, negedge b))) ++n_comma;
  always @(a, negedge b) ++n_comma_exp;

  int n_nested = 0;
  int n_nested_exp = 0;
  always @(b, ((posedge a))) ++n_nested;
  always @(b, posedge a) ++n_nested_exp;

  initial begin
    for (int i = 0; i < 37; ++i) begin
      #1;
      en = i[2];
      a = i[0];
      b = i[1] ^ i[3];
    end
    #1;
    `checkd(n_edges, n_edges_exp);
    `checkd(n_or, n_or_exp);
    `checkd(n_comma, n_comma_exp);
    `checkd(n_nested, n_nested_exp);
    `checkd(n_edges, 25);
    $write("*-* All Finished *-*\n");
    $finish;
  end

  int n_wait = 0;
  initial begin
    @((posedge a) or (negedge b));
    ++n_wait;
    `checkd($time, 2);
    @((posedge a) or (negedge b));
    ++n_wait;
    `checkd($time, 4);
    @((a iff en));
    ++n_wait;
    `checkd($time, 5);
    `checkd(n_wait, 3);
  end
endmodule
