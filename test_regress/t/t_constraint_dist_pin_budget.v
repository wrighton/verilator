// DESCRIPTION: Verilator: Bound optional diversity work after a weighted draw
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(got, exp) do if ((got) !== (exp)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__, `__LINE__, (got), (exp)); `stop; end while (0);
// verilog_format: on

class DiversityBudget;
  rand bit [3:0] pick, bias;
  rand bit [7:0] values[2000];
  constraint c {
    bias == 0;
    (pick + bias) dist {4'd3 := 1, 4'd7 := 2};
    foreach (values[i]) values[i][0] == 1'b0;
  }
endclass

module t;
  initial begin
    automatic DiversityBudget obj = new;
    int ok;
    bit varied;
    obj.srandom(311);
    ok = obj.randomize();
    `checkd(ok, 1);
    `checkd((obj.pick inside {4'd3, 4'd7}), 1'b1);
    varied = 0;
    foreach (obj.values[i]) begin
      `checkd(obj.values[i][0], 1'b0);
      varied |= obj.values[i] != obj.values[0];
    end
    `checkd(varied, 1'b1);
    $display("Pin-budget pick %0d", obj.pick);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
