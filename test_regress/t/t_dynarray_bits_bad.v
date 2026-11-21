// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;
  typedef int dyn_t[];
  typedef byte queue_t[$];
  int n;
  logic [15:0] v;
  initial begin
    n = $bits(dyn_t);
    n = $bits(queue_t);
    v = {<<queue_t{v}};
  end
endmodule
