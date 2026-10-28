// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;
  typedef int dyn_t[];
  typedef byte queue_t[$];
  int n;
  initial begin
    n = $bits(dyn_t);
    n = $bits(queue_t);
  end
endmodule
