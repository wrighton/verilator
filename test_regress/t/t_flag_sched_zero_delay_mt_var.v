// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module t;
  logic clk = 1'b0;
  int cyc = 0;
  bit x = 1'b0;
  int r[4] = '{default: 0};

  // Clocked logic reading the value set after a delay of unknown value
  for (genvar i = 0; i < 4; ++i) begin : g
    always_ff @(posedge clk) r[i] <= r[i] + i + int'(x);
  end

  int delay;
  initial begin
    delay = $urandom_range(0, 0);
    // verilator lint_off ZERODLY
    #(delay) x = 1'b1;
    // verilator lint_on ZERODLY
  end

  always #5 clk = ~clk;

  always @(posedge clk) begin
    cyc <= cyc + 1;
    if (cyc == 3) begin
      for (int i = 0; i < 4; ++i) `checkd(r[i], 3 * (i + 1));
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
