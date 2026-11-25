// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module slot;
  /* verilator no_inline_module */
  int tmp;
endmodule

// One process using a temporary of each of two instances of the same module
module core (
    input bit clk,
    input int a,
    input int b,
    output int q[64],
    output int r
);
  slot s0 ();
  slot s1 ();
  always @(posedge clk) begin
    s0.tmp = a;
    s1.tmp = b;
    if (a != 0) begin
      for (int k = 0; k < 64; ++k) begin
        if (k[0]) q[k] <= s0.tmp + 3 * s1.tmp + k;
        else q[k] <= 5 * s0.tmp - s1.tmp - k;
      end
      // One instance's temporary written, the other's only read
      s0.tmp = s0.tmp + 7;
      r <= s0.tmp * 11 - s1.tmp;
    end
  end
endmodule

module t;
  bit clk = 0;
  int cyc = 0;
  int a = 0;
  int b = 0;
  int q[64];
  int r;
  core u (.*);

  initial forever #1 clk = ~clk;

  always @(negedge clk) begin
    cyc <= cyc + 1;
    a <= 3 * cyc + 6;
    b <= 5 * cyc + 29;
    if (cyc > 1) begin
      for (int k = 0; k < 64; ++k) `checkd(q[k], k[0] ? a + 3 * b + k : 5 * a - b - k);
      `checkd(r, (a + 7) * 11 - b);
    end
    if (cyc == 20) begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
