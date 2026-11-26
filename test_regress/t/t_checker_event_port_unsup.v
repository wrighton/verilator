// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// IEEE 1800-2023 17.3 example
checker Mutex (logic [31:0] sig, event clock, output bit failure);
  assert property (@clock $onehot0(sig)) failure = 1'b0;
  else failure = 1'b1;
endchecker

module t (
    input clk
);
  int cyc = 0;
  bit failure;
  Mutex check_bus (cyc, posedge clk, failure);
  Mutex check_named (.sig(cyc), .clock(negedge clk), .failure(failure));
  Mutex check_or (cyc, posedge clk or negedge clk, failure);
  Mutex check_list (.sig(cyc), .clock(posedge clk, negedge clk), .failure(failure));
endmodule
