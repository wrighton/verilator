// DESCRIPTION: Verilator: Upward assertion control name continuing outside its first scope
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module mid;
  initial $assertoff(0, gb.c);
endmodule

module leaf;
  initial check : assert (1'b1);
endmodule

// c is in par, not in gb, so gb.c names no scope (IEEE 1800-2023 23.6)
module par;
  if (1) begin : gb
    if (1) begin : inner
      initial check : assert (1'b1);
    end
  end
  leaf c ();
  mid m ();
endmodule

module t;
  par p0 ();
  par p1 ();
endmodule
