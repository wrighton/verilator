// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// With --x-initial-edge, 'a' has an X->0 change and negedge at initialization, but an event
// qualified with 'iff' only when its condition is true (IEEE 1800-2023 9.4.2.3)

module t (
    input clk
);
  logic a = 1'b0;
  logic en_1 = 1'b1;
  logic en_0 = 1'b0;
  int cnt_change_1 = 0;
  int cnt_change_0 = 0;
  int cnt_neg_1 = 0;
  int cnt_neg_0 = 0;
  int cyc = 0;

  always @(a iff en_1) cnt_change_1 = cnt_change_1 + 1;
  always @(a iff en_0) cnt_change_0 = cnt_change_0 + 1;
  always @(negedge a iff en_1) cnt_neg_1 = cnt_neg_1 + 1;
  always @(negedge a iff en_0) cnt_neg_0 = cnt_neg_0 + 1;

`ifdef VERILATOR_TIMING
  initial #1;  // Makes the design use timing
`endif

  always @(posedge clk) begin
    cyc <= cyc + 1;
    if (cyc == 2) begin
      `checkd(cnt_change_1, 1);
      `checkd(cnt_change_0, 0);
      `checkd(cnt_neg_1, 1);
      `checkd(cnt_neg_0, 0);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
