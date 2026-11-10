// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 PlanV GmbH
// SPDX-License-Identifier: CC0-1.0
// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Issue #7203: virtual interface select from sub-interface instance.
// The original reproducer: vip_agent holds vip_vif; vip_driver selects
// agent.vif.tx (a vip_tx_if sub-interface) into tx_vif.

interface vip_tx_if (
    output reg Tx
);
endinterface

interface vip_if (
    output reg Tx
);
  vip_tx_if tx (Tx);
endinterface

package vip_pkg;
  typedef virtual vip_if vip_vif;
  typedef virtual vip_tx_if vip_tx_vif;

  class vip_agent;
    vip_vif vif;
  endclass

  class vip_driver;
    vip_vif vif;
    vip_tx_vif tx_vif;
    virtual function void build_phase(vip_agent agent);
      // Sub-interface select: dtype(agent.vif) -> vip_vif -> vip_if
      vif = agent.vif;
      tx_vif = agent.vif.tx;
    endfunction
    // Chained member access through sub-interface
    virtual function void drive(logic val);
      vif.tx.Tx = val;
    endfunction
  endclass
endpackage

// Arrays of sub-interface instances, selected through a virtual interface
interface leaf_if;
  int x;
  function automatic int get();
    return x;
  endfunction
endinterface

interface mid_if;
  leaf_if subs[2] ();
endinterface

interface arr_if #(
    parameter int N = 2
);
  int y;
  leaf_if subs[N] ();
  leaf_if subd[3:2][0:1] ();
  mid_if mid ();
  modport mp(input y);
endinterface

module t;
  logic wire_Tx;
  vip_if vif_inst (.Tx(wire_Tx));
  arr_if arr_inst ();
  arr_if arr_inst2 ();
  arr_if #(3) arr_inst3 ();
  virtual arr_if #(3) arr3_vif;
  virtual arr_if arr_vifs[2];
  virtual arr_if arr_vif;
  virtual arr_if.mp arr_mp_vif;
  virtual leaf_if leaf_vif;
  virtual leaf_if leaf_vifs[2];
  int seen;
  always @(arr_vif.subs[1].x) seen = arr_vif.subs[1].x;

  initial begin
    automatic vip_pkg::vip_agent agent = new;
    automatic vip_pkg::vip_driver driver = new;

    agent.vif = vif_inst;
    driver.vif = vif_inst;

    // Test 1 (issue reproducer): sub-interface select compiles and runs
    driver.build_phase(agent);

    // Test: tx_vif now points to the sub-interface; write through it
    driver.tx_vif.Tx = 1'b1;
    `checkd(wire_Tx, 1'b1)

    // Test: chained member write through virtual interface
    driver.drive(1'b0);
    `checkd(wire_Tx, 1'b0)

    // Test 4: arrays of sub-interfaces through a virtual interface
    arr_vif = arr_inst;
    arr_vif.subs[1].x = 22;
    arr_vif.subs[0].x = 11;
    arr_vif.subd[2][1].x = 33;
    `checkd(arr_inst.subs[1].x, 22)
    `checkd(arr_inst.subs[0].x, 11)
    `checkd(arr_inst.subd[2][1].x, 33)
    `checkd(arr_vif.subs[1].get(), 22)
    leaf_vif = arr_vif.subs[1];
    `checkd(leaf_vif.x, 22)
    leaf_vifs = arr_vif.subs;
    `checkd(leaf_vifs[0].x, 11)
    #1;
    `checkd(seen, 22)
    arr_mp_vif = arr_inst2;
    arr_mp_vif.subs[1].x = 44;
    `checkd(arr_inst2.subs[1].x, 44)
    arr_vif = arr_inst2;
    #1;
    `checkd(seen, 44)
    `checkd(arr_inst.subs[1].x, 22)
    // Deeper nesting, a parameterized interface, and an array of virtual interfaces
    arr3_vif = arr_inst3;
    arr3_vif.subs[2].x = 55;
    arr3_vif.mid.subs[1].x = 66;
    `checkd(arr_inst3.subs[2].x, 55)
    `checkd(arr_inst3.mid.subs[1].x, 66)
    arr_vifs[0] = arr_inst;
    arr_vifs[1] = arr_inst2;
    arr_vifs[1].mid.subs[0].x = 77;
    `checkd(arr_inst2.mid.subs[0].x, 77)
    `checkd(arr_vifs[0].subs[0].x, 11)

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
