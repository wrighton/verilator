// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

// The default clocking also applies to items written before its declaration (IEEE 1800-2023
// 14.12); each implicitly clocked assertion is compared with an explicitly clocked copy
module t;
  bit clk;
  bit clk2;
  int cyc;
  logic a, b;

  always #1 clk = !clk;
  always #3 clk2 = !clk2;

  int seq_fails, seq_fails_exp;
  assert property (a |=> b)
    else seq_fails++;
  assert property (@(posedge clk) a |=> b)
    else seq_fails_exp++;

  int bool_fails, bool_fails_exp;
  assert property (a || b)
    else bool_fails++;
  assert property (@(posedge clk) a || b)
    else bool_fails_exp++;

  int until_fails, until_fails_exp;
  assert property (a until b)
    else until_fails++;
  assert property (@(posedge clk) a until b)
    else until_fails_exp++;

  // A clocked procedure still gives its clock (IEEE 1800-2023 16.14.6)
  int proc_fails, proc_fails_exp;
  always @(posedge clk2) begin
    assert property (cyc % 4 != 1)
      else proc_fails++;
    assert property (a |=> b)
      else proc_fails++;
  end
  assert property (@(posedge clk2) cyc % 4 != 1)
    else proc_fails_exp++;
  assert property (@(posedge clk2) a |=> b)
    else proc_fails_exp++;

  // Cycle delays (IEEE 1800-2023 14.11)
  time zero_time;
  int delay_cyc = -1;
  initial begin
    ##0;
    zero_time = $time;
    ##3;
    delay_cyc = cyc;
  end
  // Also in a clocked procedure
  time proc_delay_start, proc_delay_time;
  always @(posedge clk2) begin
    if (cyc >= 5 && proc_delay_start == 0) begin
      proc_delay_start = $time;
      ##2;
      proc_delay_time = $time - proc_delay_start;
    end
  end

  sub_named u_named (.clk(clk), .cyc(cyc));
  sub_gen u_gen (.clk(clk), .cyc(cyc));

  default clocking @(posedge clk);
  endclocking

  always @(posedge clk) begin
    cyc <= cyc + 1;
    a <= cyc[0];
    b <= cyc[1];
    if (cyc == 20) begin
      `checkd(seq_fails, seq_fails_exp);
      `checkd(seq_fails, 4);
      `checkd(bool_fails, bool_fails_exp);
      `checkd(bool_fails, 6);
      `checkd(until_fails, until_fails_exp);
      `checkd(until_fails, 6);
      `checkd(proc_fails, proc_fails_exp);
      `checkd(proc_fails, 3);
      `checkd(proc_delay_time, 4);
      `checkd(zero_time, 1);
      `checkd(delay_cyc, 3);
      `checkd(u_named.fails, u_named.fails_exp);
      `checkd(u_named.fails, 7);
      `checkd(u_gen.g.fails, u_gen.g.fails_exp);
      `checkd(u_gen.g.fails, 7);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule

// Named clocking block made the default after its use
module sub_named (
    input clk,
    input int cyc
);
  int fails, fails_exp;

  assert property (cyc % 3 != 0)
    else fails++;
  assert property (@(posedge clk) cyc % 3 != 0)
    else fails_exp++;

  clocking cb @(posedge clk);
  endclocking
  default clocking cb;
endmodule

// Default clocking in a generate block
module sub_gen (
    input clk,
    input int cyc
);
  if (1) begin : g
    int fails, fails_exp;

    default clocking cb_gen @(posedge clk);
    endclocking

    assert property (cyc % 3 != 1)
      else fails++;
    assert property (@(posedge clk) cyc % 3 != 1)
      else fails_exp++;
  end
endmodule
