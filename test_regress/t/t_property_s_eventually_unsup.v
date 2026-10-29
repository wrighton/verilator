// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Antmicro
// SPDX-License-Identifier: CC0-1.0

module t;
  bit clk = 0;
  initial forever #1 clk = ~clk;

  localparam MAX = 3;
  integer cyc = 1;

  assert property (@(posedge clk) s_eventually ##1 1);
  assert property (@(negedge clk) s_eventually ##1 1);

  // As operand of a property operator, or of a sequence, under a multi-cycle property
  assert property (@(posedge clk) cyc[0] ##1 cyc[1] |-> (s_eventually cyc[2]) or cyc[3]);
  assert property (@(posedge clk) (s_eventually cyc[2]) and cyc[0] ##1 cyc[1]);
  assert property (@(posedge clk) cyc[0] ##1 cyc[1] |-> s_eventually (cyc[2] ##1 cyc[3]));
  assert property (@(posedge clk) cyc[0] ##1 cyc[1] |-> s_eventually (cyc[2] until cyc[3]));
  assert property (@(posedge clk) cyc[0] ##1 cyc[1] |-> s_eventually (cyc[2] |-> cyc[3]));
  assert property (@(posedge clk) cyc[0] ##1 cyc[1] |-> s_eventually (accept_on (cyc[2]) cyc[3]));
  assert property (@(posedge clk) cyc[0] ##1 cyc[1] |-> s_eventually (s_always [1:2] cyc[2]));
  assert property (@(posedge clk) cyc[0] ##1 cyc[1] |-> s_eventually (cyc[2] or s_eventually cyc[3]));

  // Action blocks of strong properties also run in the end-of-simulation check
  logic a = 1, b = 0;
  int n = 0;
  assert property (@(posedge clk) a |-> s_eventually b)
  else begin
    #1 $display("fail");
  end
  assert property (@(posedge clk) a s_until b) n = #1 n + 1;
  assert property (@(posedge clk) s_eventually b) begin
    ++n;
    wait (n == 0);
  end

  always @(posedge clk) begin
    ++cyc;
    if (cyc == MAX) begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
