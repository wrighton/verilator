// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

// A property 'or' of a boolean and a negated implication passes when the boolean holds, or
// when the antecedent holds and the consequent does not match, on its first failing check, and
// fails when the antecedent does not hold or the consequent matches (IEEE 1800-2023 16.12.3,
// 16.12.4, 16.12.7), once per attempt, against a model of each attempt

module t (
    input clk
);
  localparam int END = 300;

  int cyc = 0;
  bit [63:0] crc = 64'h1234_5678_9abc_def0;
  wire a = crc[0] | crc[3];
  wire b = crc[5] | crc[9];
  wire e = crc[13] & crc[17];
  bit ha[END + 3], hb[END + 3], he[END + 3];

  int n_pass1 = 0, n_fail1 = 0, n_pass2 = 0, n_fail2 = 0, n_pass3 = 0, n_fail3 = 0;
  int n_pass4 = 0, n_fail4 = 0;

  assert property (@(posedge clk) disable iff (cyc > END) e or not (a |-> ##1 b)) ++n_pass1;
  else ++n_fail1;
  assert property (@(posedge clk) disable iff (cyc > END) not (a |=> ##1 b) or e) ++n_pass2;
  else ++n_fail2;
  assert property (@(posedge clk) disable iff (cyc > END) e or not (a |-> b ##1 b)) ++n_pass3;
  else ++n_fail3;
  assert property (@(posedge clk) disable iff (cyc > END) e or not (a |=> b)) ++n_pass4;
  else ++n_fail4;

  // Outcome of an attempt from s whose consequent checks b on the ticks from s + first to
  // s + last: count it on the tick it resolves, up to END
  task automatic expect_attempt(int s, int first, int last, inout int p, inout int f);
    if (he[s]) begin
      ++p;
      return;
    end
    if (!ha[s]) begin
      ++f;
      return;
    end
    for (int k = first; k <= last; ++k) begin
      if (!hb[s+k]) begin
        if (s + k <= END) ++p;
        return;
      end
    end
    if (s + last <= END) ++f;
  endtask

  always @(posedge clk) begin
    cyc <= cyc + 1;
    crc <= {crc[62:0], crc[63] ^ crc[2] ^ crc[0]};
    if (cyc <= END + 2) begin
      ha[cyc] = a;
      hb[cyc] = b;
      he[cyc] = e;
    end
    if (cyc == END + 3) begin
      automatic int p1 = 0, f1 = 0, p2 = 0, f2 = 0, p3 = 0, f3 = 0;
      for (int s = 0; s <= END; ++s) begin
        expect_attempt(s, 1, 1, p1, f1);
        expect_attempt(s, 2, 2, p2, f2);
        expect_attempt(s, 0, 1, p3, f3);
      end
      `checkd(n_pass1, p1);
      `checkd(n_fail1, f1);
      `checkd(n_pass2, p2);
      `checkd(n_fail2, f2);
      `checkd(n_pass3, p3);
      `checkd(n_fail3, f3);
      `checkd(n_pass4, p1);
      `checkd(n_fail4, f1);
      if (p1 == 0 || f1 == 0) `stop;
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
