// DESCRIPTION: Verilator: Assertion control scope with a variable index
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;
  for (genvar gi = 0; gi < 2; ++gi) begin : g
    initial check : assert (1'b1);
  end
  int i = 0;
  initial begin
    // A hierarchical_identifier selects a generate scope by a constant index only
    // (IEEE 1800-2023 23.6)
    $assertoff(0, g[i]);
  end
endmodule
