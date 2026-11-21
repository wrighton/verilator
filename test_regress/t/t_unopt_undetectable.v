// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0)
// verilog_format: on

// A combinational cycle through a queue, whose changes cannot be detected, and a bit, whose
// changes can be, so the cycle is broken on the bit
module t (
    input clk
);

  logic seed = 1'b0;
  // The cycle is real, so it warns however it is broken
  // verilator lint_off UNOPTFLAT
  logic [94:0] b;
  int q[$];
  int r[$];
  // verilator lint_on UNOPTFLAT

  always_comb begin
    q = {32'(seed | b[0]), 32'd0};
    r = {32'd0, 32'(seed | b[0])};
  end

  always_comb b = {94'd0, q[0][0] | r[1][0]};

  // The same cycle with several parallel paths of detectable values, which merge into one
  // edge whose weight must stay below that of the queue. It passes on an unfixed tree only
  // because the cut there happens to fall elsewhere; the arm above is the discriminator.
  // verilator lint_off UNOPTFLAT
  logic [94:0] pb;
  int pq[$];
  // verilator lint_on UNOPTFLAT
  logic [94:0] par[16];
  always_comb begin
    pq = {32'(seed | pb[0]), 32'd0};
    for (int i = 0; i < 16; ++i) par[i] = {94'd0, seed | pb[0]};
  end

  always_comb begin
    pb = {94'd0, pq[0][0]};
    for (int i = 0; i < 16; ++i) pb |= par[i];
  end

  int cyc = 0;
  always @(posedge clk) begin
    cyc <= cyc + 1;
    if (cyc == 2) seed <= 1'b1;
    if (cyc == 4) begin
      `checkd(b[0], 1);
      `checkd(q[0], 1);
      `checkd(r[1], 1);
      `checkd(pb[0], 1);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
