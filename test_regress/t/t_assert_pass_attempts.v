// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// The pass action of a concurrent assertion runs once per attempt succeeding, also when several
// attempts succeed on one tick, vacuously or not (IEEE 1800-2023 16.14.1). The counts are checked
// against attempts enumerated from the sampled values.

module sub (
    input clk,
    input a,
    input c,
    input dis
);
  // Test: with vacuous passes off, only the nonvacuous ones run
  int passes = 0;
  assert property (@(posedge clk) disable iff (dis) a [*3] |-> c) ++passes;
  else;
endmodule

module t;
  bit clk = 0;
  always #5 clk = ~clk;

  int cyc = 0;
  bit [6:0] lfsr = 7'h5a;
  always @(posedge clk) begin
    cyc <= cyc + 1;
    lfsr <= {lfsr[5:0], lfsr[6] ^ lfsr[5]};
  end
  wire a = lfsr[0];
  wire b = lfsr[2];
  wire c = lfsr[4];
  wire dis = (cyc % 17) == 11;

  initial $assertvacuousoff(0, sub_i);
  sub sub_i (.*);

  // Test: an antecedent of a fixed length, several attempts ending on one tick
  int rep_passes = 0, rep_fails = 0;
  assert property (@(posedge clk) disable iff (dis) a [*3] |-> c) ++rep_passes;
  else ++rep_fails;

  // Test: a sequence of a range, several attempts matching on one tick
  int range_passes = 0, range_fails = 0;
  assert property (@(posedge clk) a ##[1:4] b) ++range_passes;
  else ++range_fails;

  // Test: an implication with a range in its consequent
  int cons_passes = 0, cons_fails = 0;
  assert property (@(posedge clk) a |-> ##[1:3] c) ++cons_passes;
  else ++cons_fails;

  // The sampled values of each tick, to enumerate the attempts
  bit ha[$], hb[$], hc[$], hd[$];
  always @(posedge clk) begin
    ha.push_back(a);
    hb.push_back(b);
    hc.push_back(c);
    hd.push_back(dis);
  end

  initial begin
    repeat (60) @(posedge clk);
    #1;
    begin
      automatic int n = ha.size();
      automatic int rep_p = 0, rep_f = 0, rep_nv = 0;
      automatic int range_p = 0, range_f = 0, cons_p = 0, cons_f = 0;
      for (int s = 0; s < n; ++s) begin
        automatic bit resolved = 0;
        // a [*3] |-> c, disabled when dis holds on a tick of the attempt
        for (int k = 0; k < 3 && !resolved; ++k) begin
          if (s + k >= n || hd[s+k]) resolved = 1;
          else if (!ha[s+k]) begin
            resolved = 1;
            ++rep_p;
          end
        end
        if (!resolved) begin
          if (hc[s+2]) begin
            ++rep_p;
            ++rep_nv;
          end
          else ++rep_f;
        end
        // a ##[1:4] b, passing at its first match
        resolved = 0;
        if (!ha[s]) ++range_f;
        else begin
          for (int k = 1; k <= 4 && !resolved; ++k) begin
            if (s + k < n && hb[s+k]) begin
              resolved = 1;
              ++range_p;
            end
          end
          if (!resolved && s + 4 < n) ++range_f;
        end
        // a |-> ##[1:3] c
        resolved = 0;
        if (!ha[s]) ++cons_p;
        else begin
          for (int k = 1; k <= 3 && !resolved; ++k) begin
            if (s + k < n && hc[s+k]) begin
              resolved = 1;
              ++cons_p;
            end
          end
          if (!resolved && s + 3 < n) ++cons_f;
        end
      end
      `checkd(rep_passes, rep_p);
      `checkd(rep_fails, rep_f);
      `checkd(sub_i.passes, rep_nv);
      `checkd(range_passes, range_p);
      `checkd(range_fails, range_f);
      `checkd(cons_passes, cons_p);
      `checkd(cons_fails, cons_f);
      // The stimulus has ticks on which several attempts pass
      `checkd(rep_p, 49);
      `checkd(range_p, 31);
      `checkd(cons_p, 58);
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
