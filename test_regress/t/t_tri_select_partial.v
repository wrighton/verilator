// DESCRIPTION: Verilator: Tristate drivers of partly out-of-range constant selects
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module drive_pulled (
    output wire [1:0] p
);
  pullup (p[0]);
  pulldown (p[1]);
endmodule

module t;
  bit clk = 0;
  always #1 clk = ~clk;
  int cycle = 0;
  logic en;
  assign en = cycle[0];

  // Disjoint constant-select drivers share resolution logic. One is partly out of range, so
  // only its bit within the vector is driven, from its value's upper bit (IEEE 1800-2023 11.5.1).
  wire [7:0] bus;
  // verilator lint_off SELRANGE
  assign bus[0-:2] = en ? 2'b11 : 2'bzz;
  // verilator lint_on SELRANGE
  assign bus[7:2] = en ? 6'h2a : 6'hzz;

  // Wired-net drivers merge per element; the partly out-of-range one drives only wired[0]
  wor [7:0] wired;
  logic [1:0] wired_low;
  assign wired_low = cycle[1:0];
  // verilator lint_off SELRANGE
  assign wired[0-:2] = wired_low;
  // verilator lint_on SELRANGE
  assign wired[7:4] = 4'(cycle);

  // A pull through a port reaches only the connected bits that exist: p[1] is pulled[0]
  wire [7:0] pulled;
  pullup (pulled[1]);
  // verilator lint_off SELRANGE
  drive_pulled u_pulled (.p(pulled[0-:2]));
  // verilator lint_on SELRANGE
  // A pull of a select partly outside the net pulls only its bits within the net
  wire [7:0] pulled_direct;
  // verilator lint_off SELRANGE
  pullup (pulled_direct[0-:2]);
  // verilator lint_on SELRANGE

  always @(posedge clk) begin
    if (en) begin
      `checkh(bus[7:2], 6'h2a);
      `checkh(bus[0], 1'b1);
    end
    `checkh(wired[7:4], 4'(cycle));
    `checkh(wired[0], wired_low[1]);
    `checkh(pulled[1:0], 2'b10);
    `checkh(pulled_direct[0], 1'b1);
    if (cycle == 5) begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
    cycle <= cycle + 1;
  end
endmodule
