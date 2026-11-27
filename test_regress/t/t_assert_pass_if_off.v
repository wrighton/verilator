// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// A pass action that is an 'if' statement does not run after $assertpassoff, and runs again
// after $assertpasson (IEEE 1800-2023 20.11)

module t (
    input clk
);
  int cyc = 0;
  int imm = 0;
  int conc = 0;

  initial $assertpassoff;

  always @(posedge clk) begin
    cyc <= cyc + 1;
    // Test: immediate assertion
    assert (1)
      if (cyc >= 0) imm++;
  end

  // Test: concurrent assertion
  assert property (@(posedge clk) 1)
    if (cyc >= 0) conc++;

  always @(negedge clk) begin
    if (cyc == 10) begin
      `checkd(imm, 0);
      `checkd(conc, 0);
      $assertpasson;
    end
    if (cyc == 20) begin
      `checkd(imm, 10);
      `checkd(conc, 10);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
