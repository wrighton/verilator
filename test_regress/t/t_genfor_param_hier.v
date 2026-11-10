// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Hierarchical references to parameters of loop generate block instances,
// including the implicit localparam of the genvar (IEEE 1800-2023 27.4)

interface ifc #(
    parameter int P = 1
);
endinterface

module sub;
  for (genvar k = 0; k < 3; k++) begin : g
    localparam int K = k + 50;
  end
endmodule

module t;
  for (genvar k = 1; k < 9; k += 3) begin : g
    localparam int K = k * 10;
    int w = k + 100;
  end

  for (genvar i = 0; i < 2; i++) begin : ga
    for (genvar j = 0; j < 3; j++) begin : gb
      localparam int IJ = i * 10 + j;
    end
  end

  if (1) begin : gi
    ifc #(.P(7)) ifcs[2] ();
  end

  sub u ();

  initial begin
    #1;
    `checkd(g[4].k, 4);
    `checkd(g[7].k, 7);
    `checkd(g[1].K, 10);
    `checkd(g[7].K, 70);
    `checkd(g[4].w, 104);
    `checkd($bits(g[4].k), 32);
    `checkd(ga[1].i, 1);
    `checkd(ga[1].gb[2].j, 2);
    `checkd(ga[1].gb[2].IJ, 12);
    `checkd(ga[0].gb[1].IJ, 1);
    `checkd(u.g[2].k, 2);
    `checkd(u.g[2].K, 52);
    `checkd(gi.ifcs[1].P, 7);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
