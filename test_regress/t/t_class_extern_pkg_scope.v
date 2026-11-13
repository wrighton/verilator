// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Out-of-block method definitions with a package-qualified class scope,
// written inside the package itself (IEEE 1800-2023 8.24)
package pkg;
  class Base;
    int x;
    function new(int init);
      x = init;
    endfunction
  endclass

  class Derived extends pkg::Base;
    extern function new(int init);
    extern function int get();
    extern task add(int v);
    class Inner;
      int y;
      extern function int get();
    endclass
  endclass

  function pkg::Derived::new(int init);
    super.new(init);
    x = x + 1;
  endfunction

  function int pkg::Derived::get();
    return x;
  endfunction

  task pkg::Derived::add(int v);
    x = x + v;
  endtask

  function int pkg::Derived::Inner::get();
    return y;
  endfunction
endpackage

class Unit;
  int z;
  extern function int get();
endclass

function int $unit::Unit::get();
  return z;
endfunction

module t;
  initial begin
    pkg::Derived d;
    pkg::Derived::Inner i;
    Unit u;
    d = new(40);
    `checkd(d.get(), 41);
    d.add(2);
    `checkd(d.get(), 43);
    i = new;
    i.y = 5;
    `checkd(i.get(), 5);
    u = new;
    u.z = 6;
    `checkd(u.get(), 6);

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
