// DESCRIPTION: Verilator: Sampled values in matured procedural assertions, in unsigned format lists
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__, `__LINE__, (gotv), (expv)); `stop; end while (0);
// verilog_format: on

// IEEE 1800-2023 16.9.3: $past(a) is the sampled value of a at the previous tick of the clock,
// also when the instance of a procedural assertion matures and its attempt begins in the
// Observed region (16.14.6), after the NBA region updated the pipeline register. a toggles at
// every clock, so $past(a) == !a (sampled), from the second clock on. Unsigned arguments of a
// format are kept as a plain list, where the previous argument is a sampled one.
module t;
  bit clk = 0;
  int cyc = 0;
  bit a = 0;
  bit [7:0] s = 8'd7;
  int np = 0, nf = 0, npe = 0, nfe = 0;
  always @(posedge clk) begin
    a <= ~a;
    assert property (cyc == 0 || $sformatf(
        "%0d%0d", s, $past(a)
    ) == $sformatf(
        "%0d%0d", s, !a
    ))
      ++np;
    else ++nf;
    assert property ((cyc == 0 || $sformatf(
        "%0d%0d", s, $past(a)
    ) == $sformatf(
        "%0d%0d", s, !a
    )) until_with 1)
      ++npe;
    else ++nfe;
  end
  always #5 clk = ~clk;
  always @(posedge clk) cyc <= cyc + 1;
  always @(negedge clk) begin
    if (cyc == 6) begin
      `checkd(np, 6);
      `checkd(nf, 0);
      `checkd(npe, 6);
      `checkd(nfe, 0);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
