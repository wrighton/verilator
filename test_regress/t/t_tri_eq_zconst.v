// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv, expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0x exp=%0x (%s !== %s)\n", `__FILE__, `__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

module t (
    input clk
);

  int cyc = 0;
  wire [6:0] a = cyc[6:0];

  // '?' is z; z bits of == and != operands act as x (IEEE 1800-2023 11.4.5)
  assert property (@(posedge clk) a == 7'b??????1 |-> a[0]);

  always @(posedge clk) begin
    cyc <= cyc + 1;
    `checkh(a[0] == cyc[0], 1'b1);
    if (a[1:0] != 2'b10) begin
      `checkh(a == 7'bzzzzz10, 1'b0);
      `checkh(7'b?????10 == a, 1'b0);
      `checkh(a != 7'bzzzzz10, 1'b1);
    end
    if (cyc == 9) begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
