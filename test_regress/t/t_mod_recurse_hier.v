// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Hierarchical references through several levels of a recursively instantiated module

module rec #(
    parameter int N = 3
) (
    input int in,
    output int depth,
    output int sum
);
  if (N == 0) begin : g_leaf
    assign depth = 0;
    assign sum = in;
  end
  else begin : g_node
    int d;
    int s;
    int w;
    rec #(.N(N - 1)) u (
        .in(in + N),
        .depth(d),
        .sum(s)
    );
    assign depth = d + 1;
    assign sum = s;
    function int f(input int v);
      return v * N;
    endfunction
    task tsk(input int v);
      w = v + N;
    endtask
    if (N == 3) begin : g_chk
      int inner;
      assign inner = u.g_node.u.depth;
    end
  end
endmodule

module t (
    input clk
);
  int cyc = 0;
  int depth;
  int sum;

  rec r (
      .in(cyc),
      .depth,
      .sum
  );

  always @(posedge clk) begin
    cyc <= cyc + 1;
    `checkd(depth, 3);
    `checkd(sum, cyc + 6);
    `checkd(r.g_node.u.depth, 2);
    `checkd(r.g_node.u.g_node.u.depth, 1);
    `checkd(r.g_node.u.g_node.u.g_node.u.depth, 0);
    `checkd(r.g_node.u.g_node.u.g_node.u.sum, cyc + 6);
    `checkd(r.g_node.u.g_node.u.g_node.d, 0);
    `checkd(r.g_node.g_chk.inner, 1);
    `checkd(r.g_node.u.g_node.f(cyc), cyc * 2);
    `checkd(r.g_node.u.g_node.u.g_node.f(cyc), cyc);
    r.g_node.u.g_node.u.g_node.tsk(cyc);
    `checkd(r.g_node.u.g_node.u.g_node.w, cyc + 1);
    if (cyc == 9) begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
