// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on


// A phased solve-before over arrays pins their elements one by one, in the restricted logic

class Phased;
  rand int unsigned n;
  rand int unsigned a[4];
  rand int unsigned d[];
  constraint c {
    n inside {[1 : 4]};
    foreach (a[i]) a[i] == n + i;
    d.size() == 3;
    foreach (d[i]) d[i] > a[0];
    solve n before a;
    solve a before d;
  }
endclass

module t;
  initial begin
    automatic Phased o = new;
    automatic int ok;
    repeat (20) begin
      ok = o.randomize();
      `checkh(ok, 1);
      foreach (o.a[i]) `checkh(o.a[i], o.n + i);
      `checkh(o.d.size(), 3);
      foreach (o.d[i]) `checkh(o.d[i] > o.a[0], 1'b1);
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
