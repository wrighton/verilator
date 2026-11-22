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
  int i = 0;
  initial begin
    // A hierarchical_identifier selects a generate scope by a constant_bit_select only
    // (IEEE 1800-2023 A.9.3, 23.6)
    $assertoff(0, g[i]);
    $assertoff(0, scalar[0]);
    $assertoff(0, g[selected_index()]);
    $assertoff(0, g[selected_index() + i]);
  end
endmodule
