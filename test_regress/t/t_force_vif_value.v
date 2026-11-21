// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0)
// verilog_format: on

// What a virtual interface may still do around a force: be assigned through, and supply the
// value of a force of an ordinary signal

interface vif_force_if;
  logic [7:0] sig;
endinterface

class Driver;
  virtual vif_force_if m_vif;
  task write(logic [7:0] v);
    m_vif.sig = v;  // an ordinary assignment through the interface
  endtask
endclass

module t;
  logic [7:0] y = 8'h00;
  vif_force_if i ();
  virtual vif_force_if vh;

  initial begin
    automatic Driver d = new;
    d.m_vif = i;
    vh = i;
    d.write(8'h5a);
    #1 `checkh(i.sig, 8'h5a);
    force y = vh.sig;  // only the value is read through the interface
    #1 `checkh(y, 8'h5a);
    d.write(8'ha5);
    #1 `checkh(y, 8'ha5);
    release y;
    #1 `checkh(y, 8'ha5);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
