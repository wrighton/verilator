// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

interface ifc #(
    parameter int W = 4
);
  logic clk;
  logic [W-1:0] d;
  modport mon(input clk, input d);
endinterface

// Use as a virtual interface keeps the interface alive, unlike in t_interface_top_bad
package p;
  class c #(
      int W = 4
  );
    virtual ifc #(W) vif;
  endclass
endpackage

// An instance in another top module also keeps the interface alive
interface ifc2;
  logic clk;
endinterface

module t (
    ifc bus,
    ifc.mon mon_bus,
    ifc2 bus2
);
  int n;
  always @(posedge bus.clk) n <= n + int'(bus.d);
  always @(posedge mon_bus.clk) n <= n + int'(mon_bus.d);
  always @(posedge bus2.clk) n <= n + 1;
endmodule

module t_other;
  ifc2 u ();
endmodule
