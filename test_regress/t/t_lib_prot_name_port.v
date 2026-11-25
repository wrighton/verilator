// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

`ifndef CONSUMER
// Libraries with internal markers in their names and ports named like functions of their wrappers
module t (
    input bit clk,
    input bit lib__DOT__name_protectlib_combo_update,
    output bit q
);
  always_ff @(posedge clk) q <= lib__DOT__name_protectlib_combo_update;
endmodule

module marker (
    input bit clk,
    input bit leftright_protectlib_settle,
    input bit leftright_protectlib_clock_low,
    output bit q
);
  always_ff @(posedge clk) q <= leftright_protectlib_settle ^ leftright_protectlib_clock_low;
endmodule
`else
// A user of both libraries and of a C function named like the settle function of one
module consumer (
    input bit clk,
    input int n,
    output bit q_d,
    output bit q_m,
    output int y
);
  import "DPI-C" left__PVT__right_protectlib_settle =
  function int user_settle(input int n);
  lib__DOT__name u_d (
      .clk(clk),
      .lib__DOT__name_protectlib_combo_update(n[1]),
      .q(q_d)
  );
  left__PVT__right u_m (
      .clk(clk),
      .leftright_protectlib_settle(n[0]),
      .leftright_protectlib_clock_low(n[2]),
      .q(q_m)
  );
  assign y = user_settle(n);
endmodule
`endif
