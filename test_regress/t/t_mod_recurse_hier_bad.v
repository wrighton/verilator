// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Missing names in hierarchical references through several levels of a recursive module

module rec #(
    parameter int N = 3
) (
    output int depth
);
  if (N == 0) begin : g_leaf
    assign depth = 0;
  end
  else begin : g_node
    int d;
    rec #(.N(N - 1)) u (.depth(d));
    assign depth = d + 1;
  end
endmodule

module t;
  int depth;
  rec r (.depth);
  initial begin
    $display("%0d", r.g_node.u.g_node.u.g_node.nonexist);  // Bad
    $display("%0d", r.g_node.u.g_node.u.g_node.u.g_node.d);  // Bad, too deep
    $display("%0d", r.g_node.u.g_node.u.g_nonode.depth);  // Bad
    r.g_node.u.g_node.u.g_node.notask();  // Bad
    $display("%0d", r.g_node.u.g_node.u.g_node.nofunc(1));  // Bad
  end
endmodule
