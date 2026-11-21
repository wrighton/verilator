// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module drv #(
    parameter V = 1'b1
) (
    output o
);
  assign o = V;
endmodule

// IEEE 1800-2023 6.10: An implicit net is declared in the scope where the
// reference appears, e.g. only in the generate block
module t;
  // verilator lint_off IMPLICIT

  if (1) begin : g1
    drv #(1'b1) u (.o(w));
    wire r = w;
  end
  // Same name, different net
  if (1) begin : g2
    drv #(1'b0) u (.o(w));
    wire r = w;
  end
  // One net per iteration
  for (genvar i = 0; i < 2; ++i) begin : gfor
    drv #(i) u (.o(w));
  end
  // Unnamed generate block
  if (1) drv #(1'b1) u (.o(w));
  // Referenced in a lower generate block before the declaring port connection
  if (1) begin : g3
    if (1) begin : g3a
      wire r = w;
    end
    drv #(1'b1) u (.o(w));
  end
  // Module level net referenced in a generate block before the port connection
  if (1) begin : g4
    wire r = m;
  end
  drv #(1'b1) u (.o(m));
  // Continuous assignment
  if (1) begin : g5
    assign a = 1'b1;
  end
  // Else-if chain
  if (0) begin : g6
  end else if (1) begin : g6
    drv #(1'b1) u (.o(w));
  end

  // verilator lint_on IMPLICIT

  initial begin
    #1;
    `checkh(g1.w, 1'b1);
    `checkh(g1.r, 1'b1);
    `checkh(g2.w, 1'b0);
    `checkh(g2.r, 1'b0);
    `checkh(gfor[0].w, 1'b0);
    `checkh(gfor[1].w, 1'b1);
    `checkh(genblk4.w, 1'b1);
    `checkh(g3.w, 1'b1);
    `checkh(g3.g3a.r, 1'b1);
    `checkh(g4.r, 1'b1);
    `checkh(g5.a, 1'b1);
    `checkh(g6.w, 1'b1);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
