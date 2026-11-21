// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0)
// verilog_format: on

// A force keeps reading a class property whose object is reached from static storage: a
// static property, or any property through a static handle

class Obj;
  logic [7:0] m_value;
endclass

class Driver;
  static logic [7:0] s_val;
  static Driver s_self;
  logic [7:0] m_val;
  task from_static_prop();
    force t.y_prop = s_val;
  endtask
  task from_static_handle();
    force t.y_self = s_self.m_val;
  endtask
  task from_module_handle();
    force t.y_mod = t.h.m_value;
  endtask
endclass

module t;
  logic [7:0] y_prop = 8'h00;
  logic [7:0] y_self = 8'h00;
  logic [7:0] y_mod = 8'h00;
  logic [7:0] y_top = 8'h00;
  Obj h;

  initial begin
    automatic Driver d = new;
    h = new;
    Driver::s_self = d;
    Driver::s_val = 8'h5a;
    d.m_val = 8'h21;
    h.m_value = 8'h43;
    d.from_static_prop();
    d.from_static_handle();
    d.from_module_handle();
    force y_top = h.m_value;  // from module scope too
    #1;
    `checkh(y_prop, 8'h5a);
    `checkh(y_self, 8'h21);
    `checkh(y_mod, 8'h43);
    `checkh(y_top, 8'h43);
    Driver::s_val = 8'ha5;
    d.m_val = 8'h65;
    h.m_value = 8'h87;
    #1;
    `checkh(y_prop, 8'ha5);
    `checkh(y_self, 8'h65);
    `checkh(y_mod, 8'h87);
    `checkh(y_top, 8'h87);
    release y_prop;
    release y_self;
    release y_mod;
    release y_top;
    #1 `checkh(y_mod, 8'h87);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
