// DESCRIPTION: Verilator: Assertion control scope with a variable index
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;
  for (genvar gi = 0; gi < 2; ++gi) begin : g
    initial check : assert (1'b1);
  end
  if (1) begin : scalar
    initial check : assert (1'b1);
  end
  function automatic int selected_index();
    return 1;
  endfunction
  if (0) begin : omitted_cfg
    typedef enum int { SELECTED = 1 } index_t;
  end
  if (1) begin : cfg
    typedef enum bit [3:0] { SELECTED = '1 } index_t;
  end
  if (1) begin : choice
    localparam int IDX = -1;
  end else begin : choice
    localparam int IDX = 0;
  end
  int i = 0;
  initial begin
    // A hierarchical_identifier selects a generate scope by a constant_bit_select only
    // (IEEE 1800-2023 A.9.3, 23.6)
    $assertoff(0, g[i]);
    $assertoff(0, scalar[0]);
    $assertoff(0, g[selected_index()]);
    $assertoff(0, g[selected_index() + i]);
    $assertoff(0, g[omitted_cfg.SELECTED]);
    $assertoff(0, g[cfg.SELECTED]);
    $assertoff(0, g[int'(cfg.SELECTED)]);
    $assertoff(0, g[cfg.SELECTED[0]]);
    $assertoff(0, g[(choice.IDX < 32'sd0) ? i : 0]);
    // Runtime references are illegal even when the expression's value is fixed.
    $assertoff(0, g[1'b0 && i[0]]);
    $assertoff(0, g[1'b1 || i[0]]);
    $assertoff(0, g[i & 0]);
    $assertoff(0, g[0 * i]);
    $assertoff(0, g[1'b1 ? 0 : i]);
    $assertoff(0, g[i ^ i]);
    $assertoff(0, g[1'b0 && (($bits(i) + i) != 0)]);
    // Runtime system functions remain nonconstant even in an unevaluated branch.
    $assertoff(0, g[1'b0 && ($time != 0)]);
    $assertoff(0, g[1'b1 || ($time != 0)]);
    $assertoff(0, g[1'b0 && ($realtime != 0.0)]);
    $assertoff(0, g[1'b0 && ($urandom != 0)]);
    $assertoff(0, g[1'b0 && $test$plusargs("SELECT")]);
    // Out-of-range indices must not wrap to a valid hierarchy element.
    $assertoff(0, g[64'sd2147483648]);
    $assertoff(0, g[-64'sd2147483649]);
    $assertoff(0, g[95'sd4294967296]);
    $assertoff(0, g[-95'sd4294967296]);
    $assertoff(0, g[129'd4294967297]);
    $assertoff(0, g[32'h80000000]);
  end
endmodule
