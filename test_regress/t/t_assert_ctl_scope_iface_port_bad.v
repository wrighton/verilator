// DESCRIPTION: Verilator: Assertion control scopes through an interface port that it does not reach
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

package pkg;
  task automatic pk_tsk(input bit v);
    a3 : assert (v);
  endtask
endpackage

// A $unit task, not within the interface
task automatic unit_tsk();
endtask

interface ifc (
    input logic clk
);
  int n = 0;
  a1 :
  assert property (@(posedge clk) 0)
  else n++;
  modport mp(input clk);
endinterface

// Names imported into an interface, or reached through a class type in it
interface ifcpk (
    input logic clk
);
  import pkg::*;
  class C;
    static task tk();
      a2 : assert (1);
    endtask
  endclass
endinterface
interface ifcpe (
    input logic clk
);
  import pkg::pk_tsk;
endinterface

// The modport does not list the assertion, so it is not found through the port, as before
module subm (
    ifc.mp p
);
  initial $assertoff(0, p.a1);
endmodule

// A name through the port is looked up within the interface instance only
module subu (
    ifc p
);
  initial $assertoff(0, p.unit_tsk);
endmodule

// A name not visible by hierarchical reference into the interface (IEEE 1800-2023 26.3), or
// through a class type (IEEE 1800-2023 8.23)
module subpk (
    ifcpk p
);
  initial begin
    $assertoff(0, p.pk_tsk);
    $assertoff(0, p.C.tk);
  end
endmodule
module subpe (
    ifcpe p
);
  initial $assertoff(0, p.pk_tsk);
endmodule

// A name through a port from one instance, and naming nothing from another
module leafn;
  initial $assertoff(0, hh.p.a1);
endmodule
module hportn (
    ifc p
);
  leafn l ();
endmodule
module hnone;
  leafn l ();
endmodule
module wa (
    input logic clk
);
  ifc i (.clk(clk));
  hportn hh (.p(i));
endmodule
module wb;
  hnone x ();
endmodule

// A variable through a port from one instance, and a scope from another, in both orders (pins
// the mixed-instance branch rejecting the crossing instance's non-scope)
interface ifcv (
    input logic clk
);
  int n = 0;
endinterface
module leafv;
  initial $assertoff(0, holder.p.n);
endmodule
module hportv (
    ifcv p
);
  leafv l ();
endmodule
module hgenv (
    input logic clk
);
  if (1) begin : p
    if (1) begin : n
      a1 :
      assert property (@(posedge clk) 0);
    end
  end
  leafv l ();
endmodule
module wva (
    input logic clk
);
  ifcv i (.clk(clk));
  hportv holder (.p(i));
endmodule
module wvb (
    input logic clk
);
  hgenv holder (.clk(clk));
endmodule
module leafv2;
  initial $assertoff(0, holder.p.n);
endmodule
module hportv2 (
    ifcv p
);
  leafv2 l ();
endmodule
module hgenv2 (
    input logic clk
);
  if (1) begin : p
    if (1) begin : n
      a1 :
      assert property (@(posedge clk) 0);
    end
  end
  leafv2 l ();
endmodule
module wva2 (
    input logic clk
);
  ifcv i (.clk(clk));
  hportv2 holder (.p(i));
endmodule
module wvb2 (
    input logic clk
);
  hgenv2 holder (.clk(clk));
endmodule

module t;
  logic clk = 0;
  ifc i0 (.clk(clk));
  subm sm (.p(i0));
  subu su (.p(i0));
  ifcpk k0 (.clk(clk));
  subpk spk (.p(k0));
  ifcpe e0 (.clk(clk));
  subpe spe (.p(e0));
  wa wa0 (.clk(clk));
  wb wb0 ();
  wva va (.clk(clk));
  wvb vb (.clk(clk));
  wvb2 vb2 (.clk(clk));
  wva2 va2 (.clk(clk));
endmodule
