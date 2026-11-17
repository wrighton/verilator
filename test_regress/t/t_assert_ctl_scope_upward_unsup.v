// DESCRIPTION: Verilator: Upward assertion control scope reaching differently elaborated parents
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module leaf;
  initial check : assert (1'b1);
endmodule

module mid;
  initial $assertoff(0, par.gb);
endmodule

module par #(
    parameter int N = 1
);
  for (genvar i = 0; i < N; ++i) begin : g
    leaf l ();
  end
  if (1) begin : gb
    initial check : assert (1'b1);
  end
  mid m ();
endmodule

module t;
  par #(.N(1)) p0 ();
  par #(.N(2)) p1 ();
endmodule
