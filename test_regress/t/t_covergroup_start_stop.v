// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Test covergroup start() and stop(): a stopped instance collects no coverage

// verilog_format: off
`define stop $stop
`define checkr(gotv,expv) do if ((gotv) != (expv)) begin $write("%%Error: %s:%0d:  got=%f exp=%f\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module t;
  logic clk = 0;
  logic [1:0] st;
  bit en = 1;

  covergroup cg_args with function sample(bit [1:0] a);
    cp: coverpoint a iff (en) {bins x[] = {[0:3]};}
  endgroup

  covergroup cg_clk @(posedge clk);
    cp: coverpoint st {bins x[] = {[0:3]};}
  endgroup

  class Mon;
    bit [1:0] v;
    covergroup cg;
      cp: coverpoint v {bins x[] = {[0:3]};}
    endgroup
    function new();
      cg = new;
    endfunction
  endclass

  cg_args c1 = new;
  cg_args c2 = new;
  cg_clk cc = new;
  Mon m = new;

  task automatic tick(input bit [1:0] value);
    st = value;
    #1 clk = 1;
    #1 clk = 0;
  endtask

  initial begin
    c1.sample(0);
    c1.stop();
    c1.sample(1);  // Not collected; another instance is unaffected
    c2.sample(1);
    c1.stop();
    c1.sample(2);  // Still stopped
    c1.start();
    c1.start();
    c1.sample(3);
    `checkr(c1.get_inst_coverage(), 50.0);
    `checkr(c2.get_inst_coverage(), 25.0);

    tick(0);
    cc.stop();
    tick(1);
    tick(2);
    cc.start();
    tick(3);
    `checkr(cc.get_inst_coverage(), 50.0);

    m.cg.stop();
    m.v = 1;
    m.cg.sample();
    m.cg.start();
    m.v = 2;
    m.cg.sample();
    `checkr(m.cg.get_inst_coverage(), 25.0);

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
