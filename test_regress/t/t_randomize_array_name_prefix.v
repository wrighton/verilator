// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on


// Arrays whose names are a prefix of another's followed by digits keep their elements apart

class Prefixed;
  rand bit [7:0] m[];
  rand bit [7:0] m2[30];
  rand bit [7:0] m20[3];
  constraint c {
    foreach (m[i]) m[i] == 8'(i);
    m2[0] == 8'haa;
    m2[29] == 8'hbb;
    m20[1] == 8'hcc;
  }
  function new();
    m = new[64];
  endfunction
endclass

module t;
  initial begin
    automatic Prefixed o = new;
    automatic int ok;
    repeat (3) begin
      ok = o.randomize();
      `checkh(ok, 1);
      foreach (o.m[i]) `checkh(o.m[i], 8'(i));
      `checkh(o.m2[0], 8'haa);
      `checkh(o.m2[29], 8'hbb);
      `checkh(o.m20[1], 8'hcc);
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
