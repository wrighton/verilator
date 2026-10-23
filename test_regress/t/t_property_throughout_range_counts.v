// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

// Failures of an implication whose consequent has a throughout after a range delay, against a
// model of each attempt (IEEE 1800-2023 16.9.9, 16.12.7)

module t;
  bit clk = 0;
  always #5 clk = ~clk;
  int cyc = 0;
  bit [15:0] lfsr = 16'hace1;
  always @(posedge clk) begin
    cyc <= cyc + 1;
    lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
  end
  wire b = lfsr[0] & lfsr[4];
  wire c = lfsr[2] | (lfsr[7] & lfsr[8]);
  wire d = lfsr[5] | lfsr[9];

  // One attempt: the guard fails for candidate ##0 only, and candidate ##1 matches
  bit b1 = 0, g1 = 1, c1 = 0;
  int fails1 = 0;
  assert property (@(posedge clk) b1 |-> ##[0:1] (g1 throughout c1 [* 2]))
  else fails1++;
  initial begin
    repeat (4) @(negedge clk);
    {b1, g1, c1} = 3'b101;
    @(negedge clk);
    {b1, g1, c1} = 3'b011;
  end

  localparam int END = 60;
  int fails2 = 0;
  assert property (@(posedge clk) disable iff (cyc > END) b |-> ##[0:1] (d throughout c))
  else fails2++;
  bit hb[END + 1], hc[END + 1], hd[END + 1];
  always @(posedge clk) begin
    if (cyc <= END) begin
      hb[cyc] = b;
      hc[cyc] = c;
      hd[cyc] = d;
    end
  end

  initial begin
    repeat (END + 4) @(posedge clk);
    #1;
    begin : chk
      // An attempt at s fails when neither candidate matches, unless disabled before
      automatic int expected = 0;
      for (int s = 0; s < END; ++s) begin
        if (hb[s] && !(hc[s] && hd[s]) && !(hc[s+1] && hd[s+1])) ++expected;
      end
      `checkd(expected, 5);
      // Known limit: the guard fails each candidate of an attempt on its own, which fails the
      // attempt while another candidate may still match: 1 failure for the first property,
      // where its attempt passes, and 10 for the second, where 5 attempts fail
      `checkd(fails1, 1);
      `checkd(fails2, 10);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
