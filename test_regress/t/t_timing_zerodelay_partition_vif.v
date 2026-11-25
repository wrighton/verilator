// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Clocked processes accessing interface variables, run before the processes resumed from a #0
// delay accessing them through virtual interfaces

interface ifc;
  int late = 0;  // Written through a virtual interface after a #0, read by a clocked process
  int early = 0;  // Written by a clocked process, read through a virtual interface after a #0
endinterface

module t;
  logic clk = 1'b0;
  ifc i ();
  virtual ifc vi = i;

  int seen = 0;
  always @(posedge clk) seen <= i.late;
  always @(posedge clk) i.early = i.early + 1;

  int early_after = 0;
  always @(posedge clk) begin
    #0;
    vi.late = vi.late + 1;
    early_after = vi.early;
  end

  initial begin
    for (int cyc = 1; cyc <= 4; ++cyc) begin
      #5 clk = 1'b1;
      #5 clk = 1'b0;
      `checkd(seen, cyc - 1);
      `checkd(early_after, cyc);
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
