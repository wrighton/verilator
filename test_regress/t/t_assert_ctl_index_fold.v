// DESCRIPTION: Verilator: Constant folding of assertion control scope indices
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

interface ifp #(
    parameter int P = 0
);
endinterface

module sub #(
    parameter int P = 1
) (
    input bit clk,
    output int fails[4],
    ifp ip
);
  for (genvar i = 0; i < 4; ++i) begin : g
    initial fails[i] = 0;
    always @(posedge clk) begin
      labelled_check :
      assert (1'b0)
      else fails[i] <= fails[i] + 1;
    end
  end
  if (1) begin : cfg
    localparam int I = P;
  end
  // Folded with the parameter of each instance
  initial $assertoff(0, g[cfg.I + 1].labelled_check);
  // Through an interface port, the parameter of the connected instance
  initial $assertoff(0, g[ip.P].labelled_check);
endmodule

module t;
  bit clk = 0;
  always #1 clk = ~clk;
  int fails1[4];
  int fails2[4];
  ifp #(.P(0)) i0 ();
  ifp #(.P(3)) i3 ();
  ifp #(.P(7)) i7 ();
  sub #(.P(1)) s1 (.clk, .fails(fails1), .ip(i3));
  sub #(.P(2)) s2 (.clk, .fails(fails2), .ip(i0));
  if (1) begin : gb
    sub #(.P(7)) s7 (.clk, .fails(), .ip(i0));
  end
  if (1) begin : cfg
    localparam int I = 0;
  end
  if (1) begin : choice
    localparam int IDX = -1;
  end else begin : choice
    localparam int IDX = 0;
  end
  function automatic int target(int x);
    return x + 1;
  endfunction
  for (genvar i = 0; i < 10; ++i) begin : g
    int failures = 0;
    initial begin
      #1;
      labelled_check :
      assert (1'b0)
      else failures++;
    end
  end
  initial begin
    // Generate-qualified parameters fold like other constant indices.
    $assertoff(0, g[cfg.I + 1].labelled_check);
    $assertoff(0, g[int'(choice.IDX) + 3].labelled_check);
    $assertoff(0, g[(choice.IDX < 32'sd0) ? 3 : 0].labelled_check);
    // Constant function calls fold.
    $assertoff(0, g[target(3)].labelled_check);
    $assertoff(0, g[target(4)].labelled_check);
    // The parameter of an interface instance, and of a generate block of a module instance
    $assertoff(0, g[i7.P].labelled_check);
    $assertoff(0, g[s2.cfg.I + 6].labelled_check);
    // Below this module, through a generate block
    $assertoff(0, g[gb.s7.cfg.I + 2].labelled_check);
    #2;
    // Only the selected generate scopes are off.
    `checkd(g[0].failures, 1);
    `checkd(g[1].failures, 0);
    `checkd(g[2].failures, 0);
    `checkd(g[3].failures, 0);
    `checkd(g[4].failures, 0);
    `checkd(g[5].failures, 0);
    `checkd(g[6].failures, 1);
    `checkd(g[7].failures, 0);
    `checkd(g[8].failures, 0);
    `checkd(g[9].failures, 0);
    `checkd(fails1[0], 1);
    `checkd(fails1[1], 1);
    `checkd(fails1[2], 0);
    `checkd(fails1[3], 0);
    `checkd(fails2[0], 0);
    `checkd(fails2[1], 1);
    `checkd(fails2[2], 1);
    `checkd(fails2[3], 0);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
