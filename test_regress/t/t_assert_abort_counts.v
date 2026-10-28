// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);

// Failure counts of properties with at most one thread per evaluation attempt, against a
// model of each attempt. An attempt starts on every tick (IEEE 1800-2023 16.14.6). A
// synchronous abort condition is checked on every tick from the start of an attempt through
// the tick its evaluation completes (IEEE 1800-2023 16.12.14).

module t (
    input clk
);

  localparam int MAXA = 512;  // Attempts, one per tick
  int cyc = 0;
  bit [31:0] lfsr = 32'h1;
  bit b, c, abrt;

  always @(posedge clk) begin
    cyc <= cyc + 1;
    lfsr <= {lfsr[30:0], lfsr[31] ^ lfsr[21] ^ lfsr[1] ^ lfsr[0]};
    b <= lfsr[0] & lfsr[3];
    c <= lfsr[7];
    abrt <= lfsr[11] & lfsr[13] & lfsr[17];
  end

  int fail_goto3 = 0, fail_goto2c = 0, fail_delay = 0, fail_accept = 0, fail_noabort = 0;
  assert property (@(posedge clk) sync_reject_on (abrt) (b [-> 3]))
  else fail_goto3++;
  assert property (@(posedge clk) sync_reject_on (abrt) (b [-> 2] ##1 c))
  else fail_goto2c++;
  assert property (@(posedge clk) sync_reject_on (abrt) (b ##2 c))
  else fail_delay++;
  assert property (@(posedge clk) sync_accept_on (abrt) (b [-> 2] ##1 c))
  else fail_accept++;
  assert property (@(posedge clk) b [-> 2] ##1 c)
  else fail_noabort++;

  // Properties with several threads per attempt keep their counts; check they still lower
  int fail_other = 0;
  assert property (@(posedge clk) sync_reject_on (abrt) (b ##[1:2] c))
  else fail_other++;
  assert property (@(posedge clk) b [-> 1:2])
  else fail_other++;
  assert property (@(posedge clk) b [* 1:2] ##1 c)
  else fail_other++;
  assert property (@(posedge clk) b [* 2:$] ##1 c)
  else fail_other++;
  assert property (@(posedge clk) reject_on (abrt) (b [-> 2] ##1 c))
  else fail_other++;
  assert property (@(posedge clk) (b ##1 c) or (c ##1 b))
  else fail_other++;

  // Model: per attempt, the number of occurrences of b so far, or the tick of the last step
  int cnt_goto3[MAXA], cnt_goto2c[MAXA], cnt_accept[MAXA], cnt_noabort[MAXA];
  bit live_goto3[MAXA], live_goto2c[MAXA], live_delay[MAXA], live_accept[MAXA];
  bit live_noabort[MAXA];
  int exp_goto3 = 0, exp_goto2c = 0, exp_delay = 0, exp_accept = 0, exp_noabort = 0;

  always @(posedge clk) begin
    // Start this tick's attempt
    live_goto3[cyc] = 1;
    live_goto2c[cyc] = 1;
    live_delay[cyc] = 1;
    live_accept[cyc] = 1;
    live_noabort[cyc] = 1;
    for (int k = 0; k <= cyc; ++k) begin
      // sync_reject_on (abrt) (b [-> 3]): matches at the third b
      if (live_goto3[k]) begin
        if (b) ++cnt_goto3[k];
        if (abrt) begin
          ++exp_goto3;
          live_goto3[k] = 0;
        end else if (cnt_goto3[k] == 3) begin
          live_goto3[k] = 0;
        end
      end
      // sync_reject_on (abrt) (b [-> 2] ##1 c): c is checked the tick after the second b
      if (live_goto2c[k]) begin
        if (abrt) begin
          ++exp_goto2c;
          live_goto2c[k] = 0;
        end else if (cnt_goto2c[k] == 2) begin
          if (!c) ++exp_goto2c;
          live_goto2c[k] = 0;
        end else if (b) begin
          ++cnt_goto2c[k];
        end
      end
      // sync_reject_on (abrt) (b ##2 c)
      if (live_delay[k]) begin
        if (abrt) begin
          ++exp_delay;
          live_delay[k] = 0;
        end else if (k == cyc && !b) begin
          ++exp_delay;
          live_delay[k] = 0;
        end else if (k == cyc - 2) begin
          if (!c) ++exp_delay;
          live_delay[k] = 0;
        end
      end
      // sync_accept_on (abrt) (b [-> 2] ##1 c): an abort makes the attempt pass
      if (live_accept[k]) begin
        if (abrt) begin
          live_accept[k] = 0;
        end else if (cnt_accept[k] == 2) begin
          if (!c) ++exp_accept;
          live_accept[k] = 0;
        end else if (b) begin
          ++cnt_accept[k];
        end
      end
      // b [-> 2] ##1 c
      if (live_noabort[k]) begin
        if (cnt_noabort[k] == 2) begin
          if (!c) ++exp_noabort;
          live_noabort[k] = 0;
        end else if (b) begin
          ++cnt_noabort[k];
        end
      end
    end
  end

  // Compare at the end of the time step, after this tick's assertion actions
  final begin
    `checkd(fail_goto3, exp_goto3);
    `checkd(fail_goto2c, exp_goto2c);
    `checkd(fail_delay, exp_delay);
    `checkd(fail_accept, exp_accept);
    `checkd(fail_noabort, exp_noabort);
  end
  always @(posedge clk) if (cyc == 400) $finish;

endmodule
