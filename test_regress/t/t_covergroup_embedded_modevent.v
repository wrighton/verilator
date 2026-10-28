// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Test embedded covergroups whose clocking events are not members of the enclosing class:
// module and package signals, and the covergroup's own arguments

// verilog_format: off
`define stop $stop
`define checkr(gotv,expv) do if ((gotv) != (expv)) begin $write("%%Error: %s:%0d:  got=%f exp=%f\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

package p;
  logic pclk = 0;
  logic [1:0] pst;
  class PkgMon;
    covergroup cg @(posedge pclk);
      cp: coverpoint pst;
    endgroup
    function new();
      cg = new;
    endfunction
  endclass
endpackage

module t;
  logic clk = 0;
  logic [1:0] st;

  class Mon;
    covergroup cg @(posedge clk);
      cp: coverpoint st;
    endgroup
    function new();
      cg = new;
    endfunction
  endclass

  class ArgMon;
    covergroup cg(int lim) @(posedge clk iff (int'(st) < lim));
      cp: coverpoint st;
    endgroup
    function new();
      cg = new(2);
    endfunction
  endclass

  class RefMon;
    covergroup cg(ref logic c) @(negedge c);
      cp: coverpoint st;
    endgroup
    function new();
      cg = new(clk);
    endfunction
  endclass

  Mon m1 = new;
  Mon m2;
  ArgMon am = new;
  RefMon rm = new;
  p::PkgMon pm = new;

  initial begin
    for (int i = 0; i < 4; ++i) begin
      st = 2'(i);
      p::pst = 2'(i);
      if (i == 2) m2 = new;  // Samples from its construction on
      #1 clk = 1;
      p::pclk = 1;
      #1 clk = 0;
      p::pclk = 0;
      #1;
    end
    `checkr(m1.cg.get_inst_coverage(), 100.0);
    `checkr(m2.cg.get_inst_coverage(), 50.0);
    `checkr(am.cg.get_inst_coverage(), 50.0);
    `checkr(rm.cg.get_inst_coverage(), 100.0);
    `checkr(pm.cg.get_inst_coverage(), 100.0);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
