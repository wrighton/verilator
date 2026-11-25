// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// A DPI import reusing results, declared in a package, so with one cache for all its callers,
// called from instances that threads would otherwise evaluate in parallel

package pkg;
  import "DPI-C" function int dpic_mt(input int x, output int payload[4096])
      /*verilator dpi_cache*/;
endpackage

module caller (
    input clk,
    input int x,
    output int y
);
  always @(posedge clk) begin
    int p[4096];
    void'(pkg::dpic_mt(x, p));
    y <= p[100];
  end
endmodule

module t (
    input clk,
    input int x0,
    input int x1,
    input int x2,
    input int x3,
    output int y0,
    output int y1,
    output int y2,
    output int y3
);
  caller u0 (
      .clk,
      .x(x0),
      .y(y0)
  );
  caller u1 (
      .clk,
      .x(x1),
      .y(y1)
  );
  caller u2 (
      .clk,
      .x(x2),
      .y(y2)
  );
  caller u3 (
      .clk,
      .x(x3),
      .y(y3)
  );
endmodule
