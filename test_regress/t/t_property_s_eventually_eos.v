// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// A strong eventually or until still pending at the end of simulation fails, once for each
// attempt (IEEE 1800-2023 16.12.11, 16.12.13). The attempts of ticks 8, 9 and 11 wait for b
// at the end, each one line in the golden output.
module t (
    input clk
);
  int cyc = 0;
  always @(posedge clk) cyc <= cyc + 1;
  wire a = cyc == 3 || cyc == 8 || cyc == 9 || cyc == 11;
  wire b = cyc == 5;
  wire c = 1'b1;
  wire rst = 1'b0;

  assert property (@(posedge clk) a |-> s_eventually b)
  else $display("EOS_OVERLAPPED");
  assert property (@(posedge clk) a |=> s_eventually b)
  else $display("EOS_NONOVERLAPPED");
  assert property (@(posedge clk) disable iff (rst) a |=> s_eventually b)
  else $display("EOS_DISABLE");
  a_vacuous_off :
  assert property (@(posedge clk) a |=> s_eventually b)
  else $display("EOS_VACUOUS_OFF");
  initial $assertvacuousoff(0, a_vacuous_off);
  assert property (@(posedge clk) a |=> (c s_until b))
  else $display("EOS_UNTIL");
  // An antecedent of two matches, of ticks 8 and 9 for the attempt of tick 7, starts two
  // threads of one attempt; the end of simulation fails the attempts pending once each
  assert property (@(posedge clk) cyc == 7 ##[1:2] c |=> s_eventually b)
  else $display("EOS_RANGE_ANTECEDENT");
  // Each pending attempt of ticks 8 and 9 has two matches of the inner antecedent waiting; the
  // attempts fail at least once in all, not once for each match
  assert property (@(posedge clk) a |-> (c ##[1:2] c |-> s_eventually b))
  else $display("EOS_INNER_RANGE_ANTECEDENT");

  always @(posedge clk) begin
    if (cyc == 14) begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
