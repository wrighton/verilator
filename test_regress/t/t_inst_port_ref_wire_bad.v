// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module sub (
    ref wire [1:0] r  // <--- Error: ref port is a net
);
endmodule

module t;
  logic [1:0] v;
  sub u_sub (.r(v));
endmodule
