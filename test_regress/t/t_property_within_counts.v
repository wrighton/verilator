// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

// An asserted 'within' with an inner sequence shorter than the outer one fails once when no
// placement of the inner sequence matches, and passes once when one does (IEEE 1800-2023
// 16.9.10), against a model of each attempt

module t (
    input clk
);
  localparam int N = 3;
  localparam int END = 400;

  int cyc = 0;
  bit [63:0] crc = 64'h5aa5_0f0f_3c3c_9696;
  // No attempt starting from END - N - 1 matches, and each fails on its first tick
  wire live = cyc < END - N - 1;
  wire a = crc[0] && live;
  wire b = crc[1];
  wire c = crc[2];
  wire d = crc[3];
  wire e = !(crc[4] && crc[5] && crc[6]);
  wire f = crc[7] || crc[8];
  wire x = crc[9] && live;
  // Values of the previous cycles, the last one at [0]
  logic [N:0] ha = '0, hb = '0, hc = '0, hd = '0, he = '0, hx = '0;

  int n_pass1 = 0, n_fail1 = 0, n_cover1 = 0, n_pass6 = 0, n_fail6 = 0;
  int n_fail3 = 0, n_fail4 = 0, n_fail5 = 0;
  int n_pass7 = 0, n_fail7 = 0, n_cover7 = 0, n_pass7_exp = 0, n_fail7_exp = 0;
  int n_pass1_exp = 0, n_fail1_exp = 0, n_fail3_exp = 0, n_fail4_exp = 0, n_fail5_exp = 0;

  assert property (@(posedge clk) disable iff (cyc > END) (b ##1 c) within (a ##N d))
    ++n_pass1;
  else ++n_fail1;
  cover property (@(posedge clk) disable iff (cyc > END) (b ##1 c) within (a ##N d))
    ++n_cover1;
  // As a consequent
  assert property (@(posedge clk) disable iff (cyc > END) x |-> (b ##1 c) within (a ##N d))
  else ++n_fail3;
  // Under throughout
  assert property (@(posedge clk) disable iff (cyc > END)
                   e throughout ((b ##1 c) within (a ##N d)))
  else ++n_fail4;
  // Followed by another step
  assert property (@(posedge clk) disable iff (cyc > END) ((b ##1 c) within (a ##N d)) ##1 f)
  else ++n_fail5;
  // Of one length, as the intersect of its operands
  assert property (@(posedge clk) disable iff (cyc > END) (c ##1 c) within (d ##1 !b))
    ++n_pass7;
  else ++n_fail7;
  cover property (@(posedge clk) disable iff (cyc > END) (c ##1 c) within (d ##1 !b))
    ++n_cover7;
  // Negated, a failure is a pass
  assert property (@(posedge clk) disable iff (cyc > END) not ((b ##1 c) within (a ##N d)))
    ++n_pass6;
  else ++n_fail6;

  always @(posedge clk) begin
    bit ok;
    cyc <= cyc + 1;
    crc <= {crc[62:0], crc[63] ^ crc[2] ^ crc[0]};
    ha <= {ha[N-1:0], a};
    hb <= {hb[N-1:0], b};
    hc <= {hc[N-1:0], c};
    hd <= {hd[N-1:0], d};
    he <= {he[N-1:0], e};
    hx <= {hx[N-1:0], x};
    if (cyc <= END) begin
      // An attempt without a fails at once
      if (!a) begin
        ++n_fail1_exp;
        ++n_fail4_exp;
        ++n_fail5_exp;
      end
      if (x && !a) ++n_fail3_exp;
      if (!(c && d)) ++n_fail7_exp;
      if (cyc >= 1 && hc[0] && hd[0]) begin
        if (c && !b) ++n_pass7_exp;
        else ++n_fail7_exp;
      end
      // The attempt started N cycles ago, with a, ends now
      if (cyc >= N && ha[N-1]) begin
        ok = d && |(hb[N-1:0] & {hc[N-2:0], c});
        if (ok) ++n_pass1_exp;
        else ++n_fail1_exp;
        if (hx[N-1] && !ok) ++n_fail3_exp;
        if (!(ok && e && &he[N-1:0])) ++n_fail4_exp;
      end
      // ... and with its next step, the attempt started N + 1 cycles ago ends now
      if (cyc >= N + 1 && ha[N]) begin
        ok = hd[0] && |(hb[N:1] & hc[N-1:0]);
        if (!(ok && f)) ++n_fail5_exp;
      end
    end
    if (cyc == END + 3) begin
      `checkd(n_pass1, n_pass1_exp);
      `checkd(n_fail1, n_fail1_exp);
      `checkd(n_cover1, n_pass1_exp);
      `checkd(n_fail3, n_fail3_exp);
      `checkd(n_fail4, n_fail4_exp);
      `checkd(n_fail5, n_fail5_exp);
      `checkd(n_pass7, n_pass7_exp);
      `checkd(n_fail7, n_fail7_exp);
      `checkd(n_cover7, n_pass7_exp);
      `checkd(n_pass6, n_fail1_exp);
      `checkd(n_fail6, n_pass1_exp);
      if (n_fail1 == 0 || n_pass1 == 0 || n_fail3 == 0) `stop;
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
