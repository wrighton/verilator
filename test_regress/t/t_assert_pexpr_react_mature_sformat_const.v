// DESCRIPTION: Verilator: const' inputs after sampled unsigned format arguments of matured assertions
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__, `__LINE__, (gotv), (expv)); `stop; end while (0);
// verilog_format: on

// IEEE 1800-2023 16.14.6.1: a const' input of a procedural concurrent assertion takes its value when
// the instance is queued at its statement. The statement runs twice per clock, with k = cyc + i;
// each instance must compare its own queued value with the sampled cyc plus its own i. Unsigned
// format arguments are kept as a plain list, where the const' input follows a sampled argument.
module t;
  bit clk = 0;
  int cyc = 0;
  bit [7:0] s = 8'd7;
  int np = 0, nf = 0;
  always #5 clk = ~clk;
  always @(posedge clk) cyc <= cyc + 1;
  always @(posedge clk) begin
    for (int i = 0; i < 2; i++) begin
      automatic bit [7:0] k = 8'(cyc + i);
      assert property ($sformatf(
          "%0d%0d", s, const'(k)
      ) == $sformatf(
          "%0d%0d", s, 8'(cyc + i)
      ))
        ++np;
      else ++nf;
    end
  end
  always @(negedge clk) begin
    if (cyc == 6) begin
      `checkd(np, 12);
      `checkd(nf, 0);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
