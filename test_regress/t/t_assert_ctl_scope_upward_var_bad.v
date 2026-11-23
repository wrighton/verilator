// DESCRIPTION: Verilator: Upward assertion control name that is a variable in one elaboration
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module mid;
  initial $assertoff(0, par.gb.x);
endmodule

module par #(
    parameter int N = 1
);
  if (N == 1) begin : gb
    if (1) begin : x
      initial check : assert (1'b1);
    end
  end
  else begin : gb
    // Here the name is a variable, not a scope or assertion (IEEE 1800-2023 20.11)
    int x = 0;
  end
  mid m ();
endmodule

module t;
  par #(.N(2)) p0 ();
  par #(.N(1)) p1 ();
endmodule
