// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

// A property 'or' of a boolean and an implication passes when the boolean holds, or when the
// implication holds, also vacuously, and fails when neither does (IEEE 1800-2023 16.12.4,
// 16.12.7), once per attempt, against a model of each attempt

module t (
    input clk
);
  localparam int END = 300;

  int cyc = 0;
  bit [63:0] crc = 64'h1234_5678_9abc_def0;
  wire a = crc[0] | crc[3];
  wire b = crc[5] | crc[9];
  wire e = crc[13] & crc[17];
  wire c = crc[21] | crc[25];
  bit ha[END + 3], hb[END + 3], he[END + 3];

  int n_pass1 = 0, n_fail1 = 0, n_pass2 = 0, n_fail2 = 0, n_pass3 = 0, n_fail3 = 0;
  int n_pass4 = 0, n_fail4 = 0, n_pass5 = 0, n_fail5 = 0, n_pass6 = 0, n_fail6 = 0;
  int n_pass7 = 0, n_fail7 = 0, n_pass8 = 0, n_fail8 = 0, n_pass9 = 0, n_fail9 = 0;

  assert property (@(posedge clk) disable iff (cyc > END) e or (a |-> ##2 b)) ++n_pass1;
  else ++n_fail1;
  assert property (@(posedge clk) disable iff (cyc > END) (a |-> ##2 b) or e) ++n_pass2;
  else ++n_fail2;
  assert property (@(posedge clk) disable iff (cyc > END) e or (a |=> ##1 b)) ++n_pass3;
  else ++n_fail3;
  // Known limit: with another implication in the implication, the vacuous passes of the outer
  // one are not seen, so these counts are those of the lowering without them
  assert property (@(posedge clk) disable iff (cyc > END) e or (a |=> not (c |=> b))) ++n_pass4;
  else ++n_fail4;
  assert property (@(posedge clk) disable iff (cyc > END) e or (a |-> not (c |=> b))) ++n_pass5;
  else ++n_fail5;
  assert property (@(posedge clk) disable iff (cyc > END) e or (a |=> not (c |-> b))) ++n_pass6;
  else ++n_fail6;
  // A consequent whose check of one tick fails an attempt that the check of the next tick
  // fails for the previous attempt
  assert property (@(posedge clk) disable iff (cyc > END) e or (a |-> always [0:1] b))
    ++n_pass8;
  else ++n_fail8;
  assert property (@(posedge clk) disable iff (cyc > END) e or (a |=> always [0:1] b))
    ++n_pass9;
  else ++n_fail9;
  // Known limit: in a nested 'or', the attempts passing on one tick count once
  assert property (@(posedge clk) disable iff (cyc > END) e or (c or (a |-> ##2 b))) ++n_pass7;
  else ++n_fail7;
  // Also lowered, with no count checked: a constant boolean operand, and an antecedent of
  // several ticks
  assert property (@(posedge clk) 1'b0 or (always [1:$] a))
  else;
  assert property (@(posedge clk) b or ((a ##1 c) |-> ##1 b))
  else;

  always @(posedge clk) begin
    cyc <= cyc + 1;
    crc <= {crc[62:0], crc[63] ^ crc[2] ^ crc[0]};
    if (cyc <= END + 2) begin
      ha[cyc] = a;
      hb[cyc] = b;
      he[cyc] = e;
    end
    if (cyc == END + 3) begin
      automatic int p = 0, f = 0;
      // Count the passes and failures of attempts started on cycle s on the cycles they
      // resolve, up to END
      for (int s = 0; s <= END; ++s) begin
        if (he[s] || !ha[s]) ++p;
        else if (s + 2 <= END) begin
          if (hb[s+2]) ++p;
          else ++f;
        end
      end
      `checkd(n_pass1, p);
      `checkd(n_fail1, f);
      `checkd(n_pass2, p);
      `checkd(n_fail2, f);
      `checkd(n_pass3, p);
      `checkd(n_fail3, f);
      // Pinned to the lowering without the vacuous passes, and per attempt: 157/143
      `checkd(n_pass4, 104);
      `checkd(n_fail4, 141);
      // Per attempt: 160/141
      `checkd(n_pass5, 112);
      `checkd(n_fail5, 146);
      // Per attempt: 162/139
      `checkd(n_pass6, 107);
      `checkd(n_fail6, 139);
      // Per attempt: 290/11
      `checkd(n_pass7, 264);
      `checkd(n_fail7, 11);
      for (int o = 0; o <= 1; ++o) begin
        automatic int pa = 0, fa = 0;
        // The attempt from s holds at once with e or without a, and otherwise fails on the
        // first of ticks s + o and s + o + 1 without b
        for (int s = 0; s <= END; ++s) begin
          automatic bit done = 0;
          if (he[s] || !ha[s]) begin
            ++pa;
            done = 1;
          end
          for (int k = o; k <= o + 1 && !done && s + k <= END; ++k) begin
            if (!hb[s+k]) begin
              ++fa;
              done = 1;
            end
          end
          if (!done && s + o + 1 <= END) ++pa;
        end
        if (o == 0) begin
          `checkd(n_pass8, pa);
          `checkd(n_fail8, fa);
        end
        else begin
          `checkd(n_pass9, pa);
          `checkd(n_fail9, fa);
        end
      end
      if (p == 0 || f == 0) `stop;
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
