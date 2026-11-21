// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// A virtual interface refers to an interface instance only at run time, but a force applies
// to one signal chosen when the design is built, whatever is selected from that signal

interface vif_force_if;
  logic [7:0] sig;
  logic [7:0] arr[4];
endinterface

class Driver;
  virtual vif_force_if m_vif;
  logic [7:0] m_val;
  task whole();
    force m_vif.sig = m_val;
  endtask
  task part();
    force m_vif.sig[3:0] = m_val[3:0];
  endtask
  task bit_of();
    force m_vif.sig[2] = m_val[0];
  endtask
  task element();
    force m_vif.arr[1] = m_val;
  endtask
  task stop();
    release m_vif.sig;
  endtask
  task stop_part();
    release m_vif.sig[3:0];
  endtask
  task stop_assign();
    // verilator lint_off IEEEMAYDEPRECATE
    deassign m_vif.sig;
    // verilator lint_on IEEEMAYDEPRECATE
  endtask
endclass

module t;
  logic [7:0] y;
  vif_force_if i ();

  initial begin
    automatic Driver d = new;
    d.m_vif = i;
    d.whole();
    d.part();
    d.bit_of();
    d.element();
    d.stop();
    d.stop_part();
    d.stop_assign();
  end
endmodule
