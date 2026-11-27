// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

// An asserted sequence 'or' fails once all its operands have failed (IEEE 1800-2023 16.9.7),
// against a model of each attempt. Each attempt passes once, also when attempts with operands
// of different lengths match on one tick.

module t (
    input clk
);
  localparam int END = 400;

  int cyc = 0;
  bit [63:0] crc = 64'h5aa5_0f0f_3c3c_9696;
  // Every operand starting from END - 2 fails on its first tick, so no attempt is pending at END
  wire live = cyc < END - 2;
  wire a = crc[0] && live;
  wire b = crc[1];
  wire c = crc[2] && live;
  wire d = crc[3];
  wire e = crc[4] && crc[5] && live;
  wire x = crc[6] && live;
  // Values of the previous cycles
  logic [1:0] ha = '0, hb = '0, hc = '0, he = '0, hx = '0;

  int n_pass1 = 0, n_fail1 = 0, n_pass1_exp = 0, n_fail1_exp = 0;
  int n_pass2 = 0, n_fail2 = 0, n_pass2_exp = 0, n_fail2_exp = 0;
  int n_pass6 = 0, n_fail6 = 0;
  int n_pass7 = 0, n_pass7_exp = 0;
  int n_fail3 = 0, n_fail3_exp = 0;
  int n_pass4 = 0, n_fail4 = 0;
  int n_fail5 = 0, n_fail5_exp = 0;
  int n_pass8 = 0, n_fail8 = 0, n_pass8_exp = 0, n_fail8_exp = 0;

  // Operands of one length
  assert property (@(posedge clk) disable iff (cyc > END) (a ##1 b) or (c ##1 d))
    ++n_pass1;
  else ++n_fail1;
  // Operands of different lengths, one boolean
  assert property (@(posedge clk) disable iff (cyc > END) (a ##1 b) or (c ##2 d) or e)
    ++n_pass2;
  else ++n_fail2;
  // Negated, with operands of different lengths
  assert property (@(posedge clk) disable iff (cyc > END) not ((a ##1 b) or (c ##2 d) or e))
    ++n_pass6;
  else ++n_fail6;
  // Negated, a failure of every operand is a pass
  assert property (@(posedge clk) disable iff (cyc > END) not ((a ##1 b) or (c ##1 d)))
    ++n_pass4;
  else ++n_fail4;
  // With only a pass action, and an operand that always matches
  assert property (@(posedge clk) disable iff (cyc > END) (a ##1 b) or (1'b1 ##2 1'b1))
    ++n_pass7;
  // As a consequent
  assert property (@(posedge clk) disable iff (cyc > END) x |-> (a ##1 b) or (c ##2 d))
  else ++n_fail3;
  // Operands with no cycle delay hold or fail at once
  assert property (@(posedge clk) disable iff (cyc > END) x |-> (a ##0 b) or (c ##0 d))
  else ++n_fail5;
  // An operand that is an implication of one tick fails on its first tick
  int n_pass9 = 0, n_fail9 = 0, n_pass9_exp = 0, n_fail9_exp = 0;
  assert property (@(posedge clk) disable iff (cyc > END) (a ##1 b) or (x |-> c)) ++n_pass9;
  else ++n_fail9;
  // An operand that is an implication of one tick
  assert property (@(posedge clk) disable iff (cyc > END) e or (x |-> b)) ++n_pass8;
  else ++n_fail8;

  always @(posedge clk) begin
    cyc <= cyc + 1;
    crc <= {crc[62:0], crc[63] ^ crc[2] ^ crc[0]};
    ha <= {ha[0], a};
    hb <= {hb[0], b};
    hc <= {hc[0], c};
    he <= {he[0], e};
    hx <= {hx[0], x};
    if (cyc <= END) begin
      // An attempt whose operands all fail on its first tick fails at once
      if (!live) begin
        ++n_fail1_exp;
        ++n_fail2_exp;
      end
      if (x && !((a && b) || (c && d))) ++n_fail5_exp;
      if (x && !c && !a) ++n_fail9_exp;
      if (cyc >= 1 && hx[0] && !hc[0] && ha[0] && !b) ++n_fail9_exp;
      if (!x || c) ++n_pass9_exp;
      if (cyc >= 1 && hx[0] && !hc[0] && ha[0] && b) ++n_pass9_exp;
      if (e || !x || b) ++n_pass8_exp;
      else ++n_fail8_exp;
      // P1: the attempt started 1 cycle ago ends now
      if (cyc >= 1 && cyc - 1 < END - 2) begin
        if ((ha[0] && b) || (hc[0] && d)) ++n_pass1_exp;
        else ++n_fail1_exp;
      end
      // P7: the attempt started 1 cycle ago passes with a and b, and otherwise a cycle later
      if (cyc >= 1 && ha[0] && b) ++n_pass7_exp;
      if (cyc >= 2 && !(ha[1] && hb[0])) ++n_pass7_exp;
      // P2 and P3: the attempt started 2 cycles ago has ended by now
      if (cyc >= 2 && cyc - 2 < END - 2) begin
        if (!(he[1] || (ha[1] && hb[0]) || (hc[1] && d))) ++n_fail2_exp;
        else ++n_pass2_exp;
        if (hx[1] && !((ha[1] && hb[0]) || (hc[1] && d))) ++n_fail3_exp;
      end
    end
    if (cyc == END + 3) begin
      `checkd(n_pass1, n_pass1_exp);
      `checkd(n_fail1, n_fail1_exp);
      `checkd(n_pass2, n_pass2_exp);
      `checkd(n_fail2, n_fail2_exp);
      `checkd(n_pass6, n_fail2_exp);
      `checkd(n_pass7, n_pass7_exp);
      `checkd(n_fail6, n_pass2_exp);
      `checkd(n_fail3, n_fail3_exp);
      `checkd(n_fail5, n_fail5_exp);
      `checkd(n_pass9, n_pass9_exp);
      `checkd(n_fail9, n_fail9_exp);
      `checkd(n_pass4, n_fail1_exp);
      `checkd(n_fail4, n_pass1_exp);
      `checkd(n_pass8, n_pass8_exp);
      `checkd(n_fail8, n_fail8_exp);
      if (n_fail1 == 0 || n_fail2 == 0 || n_fail3 == 0) `stop;
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
