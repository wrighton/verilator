// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checks(gotv,expv) do if ((gotv) != (expv)) begin $write("%%Error: %s:%0d:  got='%s' exp='%s'\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Classes of the same name in different scopes, as type parameter values, make different
// specializations

package PkgReg;
  class Registry #(
      type T = int
  );
    static function T create();
      T h = new;
      return h;
    endfunction
    static function string tname();
      T h;
      return $typename(h);
    endfunction
  endclass
endpackage

package PkgA;
  class Cfg;
    typedef PkgReg::Registry#(Cfg) type_id;
    virtual function string who();
      return "PkgA::Cfg";
    endfunction
    static function Cfg get();
      Cfg h;
      h = type_id::create();
      return h;
    endfunction
  endclass
  class Outer;
    class Item;
      virtual function string who();
        return "PkgA::Outer::Item";
      endfunction
    endclass
  endclass
  class Pc #(
      type T = int
  );
    virtual function string who();
      return "PkgA::Pc";
    endfunction
  endclass
  interface class Ifc;
    pure virtual function string who();
  endclass
  class Impl implements Ifc;
    virtual function string who();
      return "PkgA::Impl";
    endfunction
  endclass
endpackage

package PkgB;
  class Cfg;
    typedef PkgReg::Registry#(Cfg) type_id;
    virtual function string who();
      return "PkgB::Cfg";
    endfunction
    static function Cfg get();
      Cfg h;
      h = type_id::create();
      return h;
    endfunction
  endclass
  class Outer;
    class Item;
      virtual function string who();
        return "PkgB::Outer::Item";
      endfunction
    endclass
  endclass
  class Pc #(
      type T = int
  );
    virtual function string who();
      return "PkgB::Pc";
    endfunction
  endclass
  interface class Ifc;
    pure virtual function string who();
  endclass
  class Impl implements Ifc;
    virtual function string who();
      return "PkgB::Impl";
    endfunction
  endclass
endpackage

// A package and a module of the same name
package dup;
  class Cfg;
    virtual function string who();
      return "package dup";
    endfunction
  endclass
endpackage

module dup;
  class Cfg;
    virtual function string who();
      return "module dup";
    endfunction
  endclass
  function automatic string who();
    Cfg h = PkgReg::Registry#(Cfg)::create();
    return h.who();
  endfunction
endmodule

class Cfg;
  typedef PkgReg::Registry#(Cfg) type_id;
  virtual function string who();
    return "$unit::Cfg";
  endfunction
endclass

class Holder #(
    type T = int
);
  T h;
  function string who();
    return h.who();
  endfunction
endclass

module sub #(
    parameter string NAME = ""
);
  class Cfg;
    virtual function string who();
      return NAME;
    endfunction
  endclass
  function automatic string who();
    Cfg h = PkgReg::Registry#(Cfg)::create();
    return h.who();
  endfunction
endmodule

module t;
  dup u_dup ();
  sub #(.NAME("s1")) s1 ();
  sub #(.NAME("s2")) s2 ();

  for (genvar i = 0; i < 2; i++) begin : g
    class Cfg;
      virtual function string who();
        return $sformatf("g[%0d]", i);
      endfunction
    endclass
    function automatic string who();
      Cfg h = PkgReg::Registry#(Cfg)::create();
      return h.who();
    endfunction
  end

  // Same-named classes in unnamed generate blocks
  if (1) begin
    class Cfg;
      virtual function string who();
        return "unnamed1";
      endfunction
    endclass
    final begin
      automatic Cfg h = PkgReg::Registry#(Cfg)::create();
      `checks(h.who(), "unnamed1");
    end
  end
  if (1) begin
    class Cfg;
      virtual function string who();
        return "unnamed2";
      endfunction
    endclass
    final begin
      automatic Cfg h = PkgReg::Registry#(Cfg)::create();
      `checks(h.who(), "unnamed2");
    end
  end

  initial begin
    PkgA::Cfg a;
    PkgB::Cfg b;
    Cfg u;
    PkgA::Outer::Item ai;
    PkgB::Outer::Item bi;
    PkgA::Pc #(int) ap;
    PkgB::Pc #(int) bp;
    automatic Holder #(PkgA::Ifc) aif = new;
    automatic Holder #(PkgB::Ifc) bif = new;
    automatic PkgA::Impl aimpl = new;
    automatic PkgB::Impl bimpl = new;

    // Same-named classes in different packages, and in $unit
    b = PkgB::Cfg::get();
    a = PkgA::Cfg::get();
    `checks(b.who(), "PkgB::Cfg");
    `checks(a.who(), "PkgA::Cfg");
    a = PkgA::Cfg::type_id::create();
    b = PkgB::Cfg::type_id::create();
    u = Cfg::type_id::create();
    `checks(a.who(), "PkgA::Cfg");
    `checks(b.who(), "PkgB::Cfg");
    `checks(u.who(), "$unit::Cfg");
    `checks(PkgA::Cfg::type_id::tname(), "class PkgA::Cfg");
    `checks(PkgB::Cfg::type_id::tname(), "class PkgB::Cfg");
    `checks(Cfg::type_id::tname(), "class $unit::Cfg");

    // Same-named nested classes
    ai = PkgReg::Registry#(PkgA::Outer::Item)::create();
    bi = PkgReg::Registry#(PkgB::Outer::Item)::create();
    `checks(ai.who(), "PkgA::Outer::Item");
    `checks(bi.who(), "PkgB::Outer::Item");

    // Specializations of same-named parameterized classes
    ap = PkgReg::Registry#(PkgA::Pc#(int))::create();
    bp = PkgReg::Registry#(PkgB::Pc#(int))::create();
    `checks(ap.who(), "PkgA::Pc");
    `checks(bp.who(), "PkgB::Pc");
    `checks(PkgReg::Registry#(PkgA::Pc#(int))::tname(), "class PkgA::Pc#(int)");
    `checks(PkgReg::Registry#(PkgB::Pc#(int))::tname(), "class PkgB::Pc#(int)");

    // Same-named interface classes
    aif.h = aimpl;
    bif.h = bimpl;
    `checks(aif.who(), "PkgA::Impl");
    `checks(bif.who(), "PkgB::Impl");

    // Same-named classes in a package and a module of the same name
    begin
      automatic dup::Cfg d = PkgReg::Registry#(dup::Cfg)::create();
      `checks(d.who(), "package dup");
      `checks(u_dup.who(), "module dup");
    end

    // Same-named classes in instances of a module
    `checks(s1.who(), "s1");
    `checks(s2.who(), "s2");

    // Same-named classes in generate blocks
    `checks(g[0].who(), "g[0]");
    `checks(g[1].who(), "g[1]");

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
