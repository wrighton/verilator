// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Combinational logic with infinite loops used to crash or hang DFG

// verilator lint_off INFINITELOOP

module t (
    input wire [3:0] a,
    output wire [3:0] q
);

  logic [3:0] empty_cond;
  always_comb begin
    empty_cond = 4'd0;
    if (a[0]) while (1);
  end

  logic [3:0] body_cond;
  always_comb begin
    body_cond = 4'd0;
    if (a[1]) while (1) body_cond = body_cond + 4'd1;
  end

  logic [3:0] empty_uncond;
  always_comb begin
    empty_uncond = 4'd0;
    while (1);
  end

  logic [3:0] body_uncond;
  always_comb begin
    body_uncond = 4'd0;
    while (1) body_uncond = body_uncond + a;
  end

  assign q = empty_cond ^ body_cond ^ empty_uncond ^ body_uncond;

endmodule
