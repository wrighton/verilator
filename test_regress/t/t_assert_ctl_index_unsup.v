// DESCRIPTION: Verilator: Nested generate path in an assertion-control index
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;
  for (genvar i = 0; i < 2; ++i) begin : cfg
    localparam int IDX = i;
  end
  for (genvar i = 0; i < 2; ++i) begin : g
    initial chk: assert (1'b1);
  end
  initial $assertoff(0, g[int'(cfg[1].IDX)].chk);

  if (1) begin : choice
    localparam int IDX = -1;
  end else begin : choice
    localparam int IDX = 0;
  end
  initial $assertoff(0, g[int'(choice.IDX)].chk);
  initial $assertoff(0, g[choice.IDX < 32'sd0].chk);
endmodule
