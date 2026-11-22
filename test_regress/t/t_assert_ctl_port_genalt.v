// DESCRIPTION: Verilator: Assertion control through a port from named generate blocks
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

interface ifc (
    input logic clk
);
  int n = 0;
  a1 :
  assert property (@(posedge clk) 0)
  else n++;
endinterface

// The alternatives of one conditional generate construct may share a name, as only one is
// instantiated (IEEE 1800-2023 27.5). Each specialization keeps one of them; each of its two
// instances names its own interface from that generate block
module sub #(
    parameter bit P = 1
) (
    ifc p
);
  if (P) begin : g
    initial $assertoff(0, p.a1);
  end
  else begin : g
    initial $assertoff(0, p);
  end
endmodule

module t;
  logic clk = 0;
  int cyc = 0;
  ifc i0 (.clk(clk));
  ifc i1 (.clk(clk));
  ifc i2 (.clk(clk));
  ifc i3 (.clk(clk));
  ifc ic (.clk(clk));
  sub #(.P(1)) s0 (.p(i0));
  sub #(.P(1)) s1 (.p(i1));
  sub #(.P(0)) s2 (.p(i2));
  sub #(.P(0)) s3 (.p(i3));

  always #5 clk = ~clk;
  always @(posedge clk) begin
    cyc <= cyc + 1;
    if (cyc == 4) begin
      `checkd(i0.n, 0);
      `checkd(i1.n, 0);
      `checkd(i2.n, 0);
      `checkd(i3.n, 0);
      `checkd(ic.n, 4);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
