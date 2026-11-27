// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on


// Many variable bits are sampled by the flat solve, as UniGen2's checks grow with them

class Wide;
  rand bit [7:0] m[300][];
  constraint c {foreach (m[i, j]) m[i][j] < 8'd200;}
  function new();
    foreach (m[i]) m[i] = new[2];
  endfunction
endclass

module t;
  initial begin
    automatic Wide o = new;
    automatic bit [7:0] prev[300];
    automatic int ok, changed;
    automatic bit seen[bit [7:0]];
    for (int n = 0; n < 3; ++n) begin
      ok = o.randomize();
      `checkh(ok, 1);
      foreach (o.m[i, j]) `checkh(o.m[i][j] < 8'd200, 1'b1);
      changed = 0;
      foreach (o.m[i]) begin
        seen[o.m[i][0]] = 1;
        if (n > 0 && o.m[i][0] != prev[i]) ++changed;
        prev[i] = o.m[i][0];
      end
      // Spread across the elements and between calls
      if (n > 0 && changed < 100) `stop;
    end
    if (seen.num() < 50) `stop;
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
