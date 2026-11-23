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
  end
endmodule
