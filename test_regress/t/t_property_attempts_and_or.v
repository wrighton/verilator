// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv, expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// A property 'and' or 'or' of operands resolving on different ticks, a 'not' among them, fails
// each failing attempt once (IEEE 1800-2023 16.12.3-16.12.5).
module t;
  localparam int N = 300;

  bit clk = 0;
  always #5 clk = ~clk;
  int cyc = 0;
  bit [63:0] crc = 64'h5aef0c8d_d70a4497;
  wire a = crc[0];
  wire b = crc[5];
  wire c = crc[9];
  wire d = crc[13];
  wire e = crc[21];

  int fails[6];
  // verilog_format: off
  assert property (@(posedge clk) disable iff (cyc < 1) (not e) and (##2 c)) else ++fails[0];
  assert property (@(posedge clk) disable iff (cyc < 1) e |-> ((not (##1 c)) or c))
  else ++fails[1];
  assert property (@(posedge clk) disable iff (cyc < 1) (d [* 3]) or (e and c)) else ++fails[2];
  assert property (@(posedge clk) disable iff (cyc < 1) (not (a ##1 e)) or (c ##2 d))
  else ++fails[3];
  assert property (@(posedge clk) disable iff (cyc < 1) (a ##1 b) or (not (c ##2 d)))
  else ++fails[4];
  assert property (@(posedge clk) disable iff (cyc < 1) not ((a ##1 b) or (c ##2 d)))
  else ++fails[5];
  // verilog_format: on

  bit ha[N], hb[N], hc[N], hd[N], he[N];
  always @(posedge clk) begin
    if (cyc < N) begin
      ha[cyc] = a;
      hb[cyc] = b;
      hc[cyc] = c;
      hd[cyc] = d;
      he[cyc] = e;
    end
    cyc <= cyc + 1;
    crc <= {crc[62:0], crc[63] ^ crc[2] ^ crc[0]};
  end

  // Whether ha..he hold on tick k, false past the last tick
  function automatic bit at(int k, int which);
    if (k >= N) return 0;
    case (which)
      0: return ha[k];
      1: return hb[k];
      2: return hc[k];
      3: return hd[k];
      default: return he[k];
    endcase
  endfunction

  always @(negedge clk) begin
    if (cyc == N) begin
      int exp[6];
      bit lhsFails, rhsFails;
      exp = '{default: 0};
      // Count each attempt failing by the last tick, N - 1
      for (int s = 1; s < N; ++s) begin
        if (at(s, 4) || (s + 2 < N && !at(s + 2, 2))) ++exp[0];
        if (s + 1 < N && at(s, 4) && !at(s, 2) && at(s + 1, 2)) ++exp[1];
        if (!(at(s, 4) && at(s, 2))
            && (!at(s, 3) || (s + 1 < N && !at(s + 1, 3)) || (s + 2 < N && !at(s + 2, 3)))) begin
          ++exp[2];
        end
        lhsFails = at(s, 0) && at(s + 1, 4);
        rhsFails = !at(s, 2) || (s + 2 < N && !at(s + 2, 3));
        if (lhsFails && rhsFails && s + 1 < N && (!at(s, 2) || s + 2 < N)) ++exp[3];
        lhsFails = !at(s, 0) || (s + 1 < N && !at(s + 1, 1));
        rhsFails = at(s, 2) && at(s + 2, 3);
        if (lhsFails && rhsFails) ++exp[4];
        if ((at(s, 0) && at(s + 1, 1)) || (at(s, 2) && at(s + 2, 3))) ++exp[5];
      end
      for (int i = 0; i < 6; ++i) `checkd(fails[i], exp[i]);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
