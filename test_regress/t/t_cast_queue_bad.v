// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;
  typedef real real_q_t[$];

  logic [39:0] w;
  real_q_t rq;

  initial begin
    rq = real_q_t'(w);  // <--- Error: a queue of reals is not a bit-stream type
    rq = real_q_t'({>>{w}});  // <--- Error
  end
endmodule
