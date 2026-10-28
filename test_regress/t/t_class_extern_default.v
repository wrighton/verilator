// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Default argument values given only in the extern prototype (IEEE 1800-2023 8.24)
class Cls;
  int sum;
  static int s_default = 7;
  int m_default = 9;
  extern virtual task respond(input int waits = 0, input bit slverr = 1'b0,
                              input bit [32:0] rdata = 33'h5);
  extern function int verbosity(int severity, int verb = (severity == 1) ? 100 : 200);
  extern function int nonconst(int a = s_default + 1, int b = m_default);
  extern function int both(int a = 4);
  class SubCls;
    extern function int sub(int x = 3);
  endclass
endclass

task Cls::respond(input int waits, input bit slverr, input bit [32:0] rdata);
  sum = waits + 32'(slverr) + 32'(rdata);
endtask

function int Cls::verbosity(int severity, int verb);
  return verb;
endfunction

function int Cls::nonconst(int a, int b);
  int result;
  result = a * 100 + b;
  return result;
endfunction

function int Cls::both(int a = 4);
  return a;
endfunction

function int Cls::SubCls::sub(int x);
  return x;
endfunction

class Derived extends Cls;
  task run();
    respond(.waits(2));
  endtask
endclass

class ClsParam #(int W = 4);
  extern function int width(int a = W);
endclass

function int ClsParam::width(int a);
  return a;
endfunction

module t;
  initial begin
    Cls c;
    Derived d;
    Cls::SubCls s;
    ClsParam #(6) p;
    c = new;
    d = new;
    s = new;
    p = new;

    c.respond();
    `checkd(c.sum, 5);
    c.respond(1);
    `checkd(c.sum, 6);
    d.run();
    `checkd(d.sum, 7);
    `checkd(c.verbosity(1), 100);
    `checkd(c.verbosity(2), 200);
    `checkd(c.verbosity(2, 3), 3);
    `checkd(c.nonconst(), 809);
    Cls::s_default = 1;
    c.m_default = 3;
    `checkd(c.nonconst(), 203);
    `checkd(c.nonconst(.b(5)), 205);
    `checkd(c.both(), 4);
    `checkd(s.sub(), 3);
    `checkd(p.width(), 6);

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
