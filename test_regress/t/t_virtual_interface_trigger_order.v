// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Members of several interfaces written through virtual interfaces. Their value-change
// triggers must be created in an order that does not depend on memory layout. The writes
// are in the reverse of the declaration order, so a trigger order following the order of
// allocation of the interfaces differs from the order of the writes.

interface ifc_a;
  int x;
endinterface

interface ifc_b;
  int x;
endinterface

interface ifc_c;
  int x;
endinterface

interface ifc_d;
  int x;
endinterface

interface ifc_e;
  int x;
endinterface

module t;
  ifc_a ua ();
  ifc_b ub ();
  ifc_c uc ();
  ifc_d ud ();
  ifc_e ue ();

  virtual ifc_a va = ua;
  virtual ifc_b vb = ub;
  virtual ifc_c vc = uc;
  virtual ifc_d vd = ud;
  virtual ifc_e ve = ue;

  int sum;
  always_comb sum = va.x + vb.x + vc.x + vd.x + ve.x;

  initial begin
    for (int i = 1; i < 10; ++i) begin
      ve.x = i;
      vd.x = 2 * i;
      vc.x = 4 * i;
      vb.x = 8 * i;
      va.x = 16 * i;
      #1;
      `checkd(sum, 31 * i);
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
