// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv, expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Several attempts of a property operator over implications passing on one tick each run the
// pass action, on that tick, though the action of another one suspends (IEEE 1800-2023 16.14.1)

module t (
    input clk
);
  localparam int NCYC = 300;

  integer cyc = 0;
  reg [63:0] crc = 64'h6b8d_1f2e_93a4_c057;

  wire a = crc[0] & crc[17];
  wire b = crc[5] | crc[29];
  wire c = crc[11] & crc[37];
  wire d = crc[23] | crc[43];
  wire e = crc[31] | crc[47];

  bit ha[NCYC + 4];
  bit hb[NCYC + 4];
  bit hc[NCYC + 4];
  bit hd[NCYC + 4];
  bit he[NCYC + 4];
  always @(posedge clk) begin
    ha[cyc] = a;
    hb[cyc] = b;
    hc[cyc] = c;
    hd[cyc] = d;
    he[cyc] = e;
  end

  int passTicks[NCYC + 4];
  int fails = 0;

  // verilog_format: off
  assert property (@(posedge clk) e |=> ((a |-> ##2 b) and (c |-> ##1 d))) begin
    automatic int start = cyc;
    ++passTicks[start];
    @(negedge clk);
  end
  else ++fails;
  // verilog_format: on

  // Whether the attempt started on tick s passes, and the tick it resolves on
  task automatic expect_attempt(int s, output bit pass, output int tick);
    tick = s;
    pass = 1;
    if (he[s]) begin
      int lhsTick = ha[s+1] ? s + 3 : s + 1;
      int rhsTick = hc[s+1] ? s + 2 : s + 1;
      bit lhsOk = !ha[s+1] || hb[s+3];
      bit rhsOk = !hc[s+1] || hd[s+2];
      // 'and' fails on the first failure of an operand, else passes when both have passed
      if (!lhsOk && (rhsOk || lhsTick < rhsTick)) tick = lhsTick;
      else if (!rhsOk) tick = rhsTick;
      else tick = lhsTick > rhsTick ? lhsTick : rhsTick;
      pass = lhsOk && rhsOk;
    end
  endtask

  always @(posedge clk) begin
    cyc <= cyc + 1;
    crc <= {crc[62:0], crc[63] ^ crc[2] ^ crc[0]};
  end

  // Check the actions of the attempts resolving before tick last
  task automatic check_actions(int last);
    int expPasses[NCYC + 4];
    int expFails = 0;
    int multiPassTicks = 0;
    for (int s = 0; s < last; ++s) begin
      bit pass;
      int tick;
      expect_attempt(s, pass, tick);
      if (tick >= last) continue;
      if (pass) ++expPasses[tick];
      else ++expFails;
    end
    for (int t = 0; t < last; ++t) begin
      `checkd(passTicks[t], expPasses[t]);
      if (expPasses[t] > 2) ++multiPassTicks;
    end
    `checkd(fails, expFails);
    // The stimulus has ticks with several pass actions, each suspending
    if (multiPassTicks < 5) `stop;
  endtask

  always @(negedge clk) begin
    if (cyc == NCYC) begin
      check_actions(NCYC - 1);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
