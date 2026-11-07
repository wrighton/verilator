// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Class parameter defaults that depend on earlier parameters (IEEE 1800-2023 6.20.1)
class Box #(
    type T = int
);
  T v;
endclass

class Env #(
    type T = byte,
    type B = Box#(.T(T)),
    type Z = int
);
  typedef Env#(T, B, Z) this_type;
  B b;
  Z z;
  function new();
    b = new;
  endfunction
  function this_type self();
    return this;
  endfunction
endclass

class Pair #(
    type X = int,
    type Y = int
);
  X x;
  Y y;
endclass

// Default depending on two parameters
class Duo #(
    type T = byte,
    type U = shortint,
    type P = Pair#(T, U)
);
  P p;
endclass

class Holder #(
    type T = int
);
  typedef T t_t;
endclass

// Default given by a class-scoped typedef
class Scoped #(
    type A = Holder#(shortint)::t_t,
    type Z = int
);
  A a;
endclass

// Type default depending on value parameters
class Vec #(
    int M = 2,
    int N = M * 2,
    type B = bit [N-1:0]
);
  B v;
endclass

package pkg;
  parameter type PT = shortint;
endpackage

// Default referencing a type parameter of a package, not of the class
class Pkgd #(
    type T = pkg::PT
);
  T v;
endclass

// Calls to the base class through the default specialization of a class whose type
// parameter default depends on another parameter (IEEE 1800-2023 8.15, 8.25.1)
class item_c;
endclass

class base_c;
  int base_new;
  function new(string name = "base");
    base_new++;
  endfunction
endclass

class seq_c #(
    type REQ = item_c,
    type RSP = REQ
) extends base_c;
  int seq_new;
  int body_calls;
  int plain_calls;
  function new(string name = "seq");
    super.new(name);
    seq_new++;
  endfunction
  virtual function void body();
    body_calls++;
  endfunction
  function void plain();
    plain_calls++;
  endfunction
endclass

// super.new with arguments, virtual and non-virtual super calls
class vseq_c extends seq_c;
  function new(string name = "vseq");
    super.new(name);
  endfunction
  virtual function void body();
    super.body();
  endfunction
  function void plain();
    super.plain();
  endfunction
endclass

// Implicit super.new
class vseq_imp_c extends seq_c;
endclass

typedef seq_c seq_t;
class vseq_td_c extends seq_t;
  function new();
    super.new("vseq_td");
  endfunction
  virtual function void body();
    super.body();
  endfunction
endclass

// Explicit specializations equal to the default
class vseq_x1_c extends seq_c #(item_c);
  function new();
    super.new();
  endfunction
  virtual function void body();
    super.body();
  endfunction
endclass

class vseq_x2_c extends seq_c #(item_c, item_c);
  virtual function void body();
    super.body();
  endfunction
endclass

class vseq2_c extends vseq_c;
  function new();
    super.new("vseq2");
  endfunction
  virtual function void body();
    super.body();
  endfunction
endclass

package seq_pkg;
  class pseq_c #(
      type T = int,
      type U = T
  );
    int calls;
    virtual function void body();
      calls++;
    endfunction
  endclass
endpackage

class vpseq_c extends seq_pkg::pseq_c;
  virtual function void body();
    super.body();
  endfunction
endclass

// Chain of dependent defaults, with a value parameter in between
class chain_c #(
    type A = item_c,
    int N = 3,
    type B = A,
    type C = B
);
  int chain_new;
  function new();
    chain_new = N;
  endfunction
  virtual function int get();
    return N;
  endfunction
endclass

class vchain_c extends chain_c;
  function new();
    super.new();
  endfunction
  virtual function int get();
    return super.get() + 10;
  endfunction
endclass

class vchain5_c extends chain_c #(.N(5));
  virtual function int get();
    return super.get() + 10;
  endfunction
endclass

// Nested parameterized class in the dependent default
class nest_c #(
    type T = item_c,
    type B = Box#(T)
);
  B b;
  function new();
    b = new;
  endfunction
  virtual function int get();
    return 1;
  endfunction
endclass

class vnest_c extends nest_c;
  function new();
    super.new();
  endfunction
  virtual function int get();
    return super.get() + 1;
  endfunction
endclass

// UVM-like sequence and sequencer hierarchies
class uvm_sequence_item;
endclass

class my_item extends uvm_sequence_item;
endclass

class uvm_sequence_base;
  int base_new;
  function new(string name = "uvm_sequence_base");
    base_new++;
  endfunction
  virtual task body();
  endtask
endclass

class uvm_sequence #(
    type REQ = uvm_sequence_item,
    type RSP = REQ
) extends uvm_sequence_base;
  typedef uvm_sequence#(REQ, RSP) this_type;
  int seq_new;
  int body_calls;
  function new(string name = "uvm_sequence");
    super.new(name);
    seq_new++;
  endfunction
  virtual task body();
    body_calls++;
  endtask
  function this_type self();
    return this;
  endfunction
endclass

class uvm_sequencer_base;
  int base_new;
  function new(string name);
    base_new++;
  endfunction
endclass

class uvm_sequencer_param_base #(
    type REQ = uvm_sequence_item,
    type RSP = REQ
) extends uvm_sequencer_base;
  int param_new;
  function new(string name);
    super.new(name);
    param_new++;
  endfunction
endclass

class uvm_sequencer #(
    type REQ = uvm_sequence_item,
    type RSP = REQ
) extends uvm_sequencer_param_base #(REQ, RSP);
  int sqr_new;
  function new(string name);
    super.new(name);
    sqr_new++;
  endfunction
endclass

class my_sequencer extends uvm_sequencer;
  function new(string name);
    super.new(name);
  endfunction
endclass

class my_item_sequencer extends uvm_sequencer #(my_item);
  function new(string name);
    super.new(name);
  endfunction
endclass

class my_vseq extends uvm_sequence;
  function new(string name = "my_vseq");
    super.new(name);
  endfunction
  virtual task body();
    super.body();
  endtask
endclass

class my_item_seq extends uvm_sequence #(my_item);
  function new(string name = "my_item_seq");
    super.new(name);
  endfunction
  virtual task body();
    super.body();
  endtask
endclass

// Module type parameter default depending on another parameter
module sub #(
    type A = byte,
    type B = Box#(A)
);
  B b = new;
endmodule

module t;
  sub u_dflt ();
  sub #(.A(shortint)) u_a ();
  sub #(.A(byte), .B(Box#(byte))) u_ab ();

  task automatic check_seq();
    automatic vseq_c v = new;
    automatic vseq_imp_c vi = new;
    automatic vseq_td_c vt = new;
    automatic vseq_x1_c vx1 = new;
    automatic vseq_x2_c vx2 = new;
    automatic vseq2_c v2 = new;
    automatic vpseq_c vp = new;
    automatic seq_c sd;
    automatic seq_c #(item_c, item_c) sx;
    `checkd(v.base_new, 1);
    `checkd(v.seq_new, 1);
    v.body();
    v.plain();
    `checkd(v.body_calls, 1);
    `checkd(v.plain_calls, 1);
    `checkd(vi.base_new, 1);
    `checkd(vi.seq_new, 1);
    `checkd(vt.seq_new, 1);
    vt.body();
    `checkd(vt.body_calls, 1);
    `checkd(vx1.seq_new, 1);
    vx1.body();
    `checkd(vx1.body_calls, 1);
    `checkd(vx2.seq_new, 1);
    vx2.body();
    `checkd(vx2.body_calls, 1);
    `checkd(v2.base_new, 1);
    `checkd(v2.seq_new, 1);
    v2.body();
    `checkd(v2.body_calls, 1);
    vp.body();
    `checkd(vp.calls, 1);
    // The default specialization is the same type however it is written
    sd = v;
    sx = sd;
    sd = vx2;
    sd.body();
    `checkd(vx2.body_calls, 2);
  endtask

  task automatic check_chain_nest();
    automatic vchain_c vc = new;
    automatic vchain5_c vc5 = new;
    automatic vnest_c vn = new;
    `checkd(vc.chain_new, 3);
    `checkd(vc.get(), 13);
    `checkd(vc5.chain_new, 5);
    `checkd(vc5.get(), 15);
    `checkd(vn.get(), 2);
  endtask

  task automatic check_uvm();
    automatic my_sequencer sqr = new("sqr");
    automatic my_item_sequencer isqr = new("isqr");
    automatic my_vseq mv = new;
    automatic my_item_seq mis = new;
    automatic uvm_sequence us;
    `checkd(sqr.base_new, 1);
    `checkd(sqr.param_new, 1);
    `checkd(sqr.sqr_new, 1);
    `checkd(isqr.sqr_new, 1);
    `checkd(mv.base_new, 1);
    `checkd(mv.seq_new, 1);
    mv.body();
    `checkd(mv.body_calls, 1);
    us = mv.self();
    us.body();
    `checkd(mv.body_calls, 2);
    `checkd(mis.seq_new, 1);
    mis.body();
    `checkd(mis.body_calls, 1);
  endtask

  initial begin
    automatic Env #(.T()) ee = new;
    automatic Env #() ed;
    automatic Pkgd #() pd = new;
    automatic Pkgd #(shortint) ps;
    automatic Env #(.Z(shortint)) ez = new;
    automatic Env #(.T(shortint)) et = new;
    automatic Env #(shortint, Box#(shortint)) et2;
    automatic Env #(.Z(shortint), .T(shortint)) etz = new;
    automatic Env #(.T(shortint), .Z(shortint)) etz2;
    automatic Duo #(.U(int)) du;
    automatic Scoped #(.Z(byte)) sz;
    automatic Vec #(.N(7)) vn;
    automatic Vec #(.M(5)) vm;
    `checkd($bits(ez.b.v), 8);
    `checkd($bits(ez.z), 16);
    `checkd($bits(et.b.v), 16);
    `checkd($bits(et.z), 32);
    // Explicitly giving a default's value is the same specialization
    et2 = et;
    et2 = et.self();
    ez = ez.self();
    `checkd($bits(et2.b.v), 16);
    // Order of named parameters does not matter
    etz2 = etz;
    `checkd($bits(etz2.b.v), 16);
    `checkd($bits(du.p.x), 8);
    `checkd($bits(du.p.y), 32);
    `checkd($bits(sz.a), 16);
    `checkd($bits(vn.v), 7);
    `checkd($bits(vm.v), 10);
    // An empty override keeps the default
    ed = ee;
    `checkd($bits(ee.b.v), 8);
    // Explicitly giving the default of a package type parameter is the same specialization
    ps = pd;
    `checkd($bits(ps.v), 16);
    `checkd($bits(u_dflt.b.v), 8);
    `checkd($bits(u_a.b.v), 16);
    `checkd($bits(u_ab.b.v), 8);
    check_seq();
    check_chain_nest();
    check_uvm();
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
