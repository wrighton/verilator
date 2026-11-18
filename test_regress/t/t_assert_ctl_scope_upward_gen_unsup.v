// DESCRIPTION: Verilator: Upward assertion control name through a farther generate block
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module mid;
  initial $assertoff(0, gb.inner);
endmodule

module par #(
    parameter bit HAS = 1
);
  if (HAS) begin : gb
    if (1) begin : inner
      initial check : assert (1'b1);
    end
    // This instance of par has no gb, so gb.inner is found in the par above it
    par #(.HAS(0)) sub ();
  end
  else begin : leaf
    mid m ();
  end
endmodule

module t;
  par p0 ();
endmodule
