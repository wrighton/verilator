// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// An implication whose consequent is an 'or' of sequences of different lengths fails once both
// operands have failed (IEEE 1800-2023 16.9.7, 16.12.7), checked against a model of each attempt

module t (
    input clk
);
  localparam int END = 300;

  int cyc = 0;
  bit [31:0] lfsr = 32'h1234_5678;
  wire a = lfsr[3];
  wire b = lfsr[9];
  wire c = lfsr[17];
  wire d = lfsr[25];
  wire e = lfsr[29];
  bit ah[END + 4], bh[END + 4], ch[END + 4], dh[END + 4], eh[END + 4];

  int fail1 = 0, fail2 = 0;
  assert property (@(posedge clk) disable iff (cyc > END) a |-> ((b ##1 c) or (d ##2 e)))
  else ++fail1;
  assert property (@(posedge clk) disable iff (cyc > END) a |=> ((b ##1 c) or (d ##2 e)))
  else ++fail2;

  // Failure tick of the attempt from s, whose consequent starts on s + o, or -1 if it passes
  function automatic int fail_tick(int s, int o);
    const int u = s + o;
    if (!ah[s]) return -1;
    if (bh[u] && ch[u+1]) return -1;
    if (dh[u] && eh[u+2]) return -1;
    // Both operands fail, at the later of their failures
    begin
      automatic int t1 = !bh[u] ? u : u + 1;
      automatic int t2 = !dh[u] ? u : u + 2;
      return t1 > t2 ? t1 : t2;
    end
  endfunction

  always @(posedge clk) begin
    cyc <= cyc + 1;
    lfsr <= {lfsr[30:0], lfsr[31] ^ lfsr[21] ^ lfsr[1] ^ lfsr[0]};
    if (cyc <= END + 3) begin
      ah[cyc] = a;
      bh[cyc] = b;
      ch[cyc] = c;
      dh[cyc] = d;
      eh[cyc] = e;
    end
    if (cyc == END + 4) begin
      automatic int exp1 = 0, exp2 = 0;
      for (int s = 0; s <= END; ++s) begin
        automatic int t1 = fail_tick(s, 0);
        automatic int t2 = fail_tick(s, 1);
        if (t1 >= 0 && t1 <= END) ++exp1;
        if (t2 >= 0 && t2 <= END) ++exp2;
      end
      `checkd(fail1, exp1);
      `checkd(fail2, exp2);
      if (exp1 == 0 || exp2 == 0) `stop;
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
