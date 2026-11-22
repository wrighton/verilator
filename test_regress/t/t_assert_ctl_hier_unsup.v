// DESCRIPTION: Verilator: Scoped assertion controls across hierarchy partitions
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module leaf (
    input bit clk,
    input bit good,
    output bit echoed
);
  /* verilator hier_block */
  always @(posedge clk) begin : checking
    check_good : assert (good) else $error("bad good");
  end
  assign echoed = good;
endmodule

module t (
    input bit clk,
    input bit good,
    output bit echoed
);
  leaf u (.clk, .good, .echoed);
  initial begin
    $assertoff(0, u);
    $assertoff(0, u.checking.check_good);
  end
endmodule
