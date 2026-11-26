// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t (
    input clk
);

  int cyc = 0;
  bit failure;
  wrap_chk check (cyc[6:0], clk, failure);

  always @(posedge clk) begin
    cyc <= cyc + 1;
    if (cyc >= 3 && cyc < 90) begin
      if (failure !== !$onehot0(cyc[6:0])) $stop;
    end
    else if (cyc == 99) begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule

// A checker instantiates another checker, passing its formals through (IEEE 1800-2023 17.2)
checker onehot_chk (input logic [6:0] sig, input bit clk, output bit failure);
  assert property (@(negedge clk) $onehot0(sig)) failure = 1'b0;
  else failure = 1'b1;
endchecker

checker wrap_chk (input logic [6:0] sig, input bit clk, output bit failure);
  onehot_chk inner (sig, clk, failure);
  logic [6:0] last_sig;
  assert property (@(negedge clk) sig == last_sig + 7'd1);
  always_ff @(posedge clk) last_sig <= sig;
endchecker
