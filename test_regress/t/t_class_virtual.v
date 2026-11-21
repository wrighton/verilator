// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2019 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`" ); `stop; end while(0);
// verilog_format: on

virtual class VBase;
  virtual function int hello;
    return 1;
  endfunction
  virtual class VNested;
    virtual function int hello;
      return 10;
    endfunction
  endclass
endclass

class VA extends VBase;
  virtual function int hello;
    return 2;
  endfunction
  class VNested extends VBase::VNested;
    virtual function int hello;
      return 20;
    endfunction
  endclass
endclass

class VB extends VBase;
  virtual function int hello;
    return 3;
  endfunction
  class VNested extends VBase::VNested;
    virtual function int hello;
      return 30;
    endfunction
  endclass
endclass

virtual class uvm_phase;
  virtual function int exec_func;
    return 0;
  endfunction
endclass

class uvm_topdown_phase extends uvm_phase;
  function int get1;
    return exec_func();
  endfunction
endclass

class uvm_build_phase extends uvm_topdown_phase;
  virtual function int exec_func;
    return 1;
  endfunction
endclass

virtual class Cls;
  uvm_phase ph;
endclass

class ExtendsCls extends Cls;
  function new;
    uvm_build_phase bp = new;
    ph = bp;
  endfunction

  function int get1;
    return super.ph.exec_func();
  endfunction
endclass

// Hiding a nonvirtual method must not make the ancestor or a sibling virtual.
package base_pkg;
  class Obj;
    extern function int pack(ref bit bits[], input int p = 0);
  endclass
  function int Obj::pack(ref bit bits[], input int p = 0);
    return p + 1;
  endfunction
  class Item extends Obj;
  endclass
endpackage

package user_pkg;
  import base_pkg::*;
  virtual class Applier extends Obj;
    pure virtual task apply();
  endclass
  class StructApplier extends Applier;
    int packed_cnt;
    virtual function void pack(string s);
      packed_cnt++;
    endfunction
    virtual task apply();
      pack("x");
    endtask
  endclass
  class SigItem extends Item;
    function bit [7:0] pack();
      return 8'h5a;
    endfunction
  endclass
endpackage

class NonvirtualBase;
  function int value(int p);
    return p + 1;
  endfunction
endclass

class EarlySibling extends NonvirtualBase;
  function int value(int p);
    return p + 4;
  endfunction
endclass

class VirtualChild extends NonvirtualBase;
  virtual function int value(int p);
    return p + 2;
  endfunction
endclass

class VirtualGrandchild extends VirtualChild;
  // The virtual keyword is not required when overriding a virtual method.
  function int value(int p);
    return p + 3;
  endfunction
endclass

class LateSibling extends NonvirtualBase;
  function int value(int p);
    return p + 5;
  endfunction
endclass

module t;
  import base_pkg::*;
  import user_pkg::*;
  initial begin
    automatic VA va = new;
    automatic VB vb = new;
    automatic VA::VNested vna = new;
    automatic VB::VNested vnb = new;
    automatic VBase b;
    automatic VBase::VNested bn;

    uvm_build_phase ph;
    ExtendsCls ec;

    begin
      StructApplier a;
      SigItem s;
      Obj o;
      bit bits[];
      a = new;
      s = new;
      o = s;
      a.apply();
      `checkd(a.packed_cnt, 1);
      `checkd(s.pack(), 8'h5a);
      `checkd(o.pack(bits, 4), 5);
    end
    begin
      NonvirtualBase b;
      EarlySibling early;
      LateSibling late;
      VirtualChild child;
      VirtualChild derived_view;
      VirtualGrandchild grandchild;
      early = new;
      late = new;
      child = new;
      grandchild = new;
      for (int p = 0; p < 4; ++p) begin
        b = early;
        `checkd(b.value(p), p + 1);
        `checkd(early.value(p), p + 4);
        b = late;
        `checkd(b.value(p), p + 1);
        `checkd(late.value(p), p + 5);
        b = child;
        `checkd(b.value(p), p + 1);
        `checkd(child.value(p), p + 2);
        b = grandchild;
        derived_view = grandchild;
        `checkd(b.value(p), p + 1);
        `checkd(derived_view.value(p), p + 3);
      end
    end
    if (va.hello() != 2) $stop;
    if (vb.hello() != 3) $stop;
    if (vna.hello() != 20) $stop;
    if (vnb.hello() != 30) $stop;

    b = va;
    bn = vna;
    if (b.hello() != 2) $stop;
    if (bn.hello() != 20) $stop;
    b = vb;
    bn = vnb;
    if (b.hello() != 3) $stop;
    if (bn.hello() != 30) $stop;

    ph = new;
    if (ph.get1() != 1) $stop;

    ec = new;
    if (ec.get1() != 1) $stop;

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
