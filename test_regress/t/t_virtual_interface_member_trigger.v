// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2025 PlanV GmbH
// SPDX-License-Identifier: CC0-1.0

`timescale 1ns / 1ps

// verilog_format: off
`define stop $stop
`define checks(gotv,expv) do if ((gotv) != (expv)) begin $write("%%Error: %s:%0d:  got='%s' exp='%s'\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define checkr(gotv,expv) do if ((gotv) != (expv)) begin $write("%%Error: %s:%0d:  got=%f exp=%f\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

typedef string str_t;
typedef real real_t;
typedef chandle chandle_t;

interface INTF;
  logic x;
  logic y;
  logic z;
  logic [7:0] data;
  str_t name;
  real value;
  real_t tvalue;
  chandle handle;
  chandle_t thandle;
endinterface

class Dummy;
  virtual INTF vif;
  function new(virtual INTF vif);
    this.vif = vif;
  endfunction
  task write_data(logic [7:0] d);
    vif.data = d;
  endtask
endclass

module t_virtual_interface_member_trigger ();
  // === Part 1: logic trigger false loop test ===
  logic s1, s2, src_val;
  INTF intf_loop ();
  virtual INTF vif_loop;
  assign intf_loop.x = s1;
  assign intf_loop.y = src_val;
  assign intf_loop.z = !intf_loop.y;
  assign s2 = intf_loop.z;
  assign s1 = s2;

  // === Part 2: data transfer chain test ===
  logic [7:0] data;
  INTF intf_read ();
  INTF intf_write ();
  assign intf_read.data = data;
  assign data = intf_write.data;
  string name;
  assign intf_read.name = name;
  assign name = intf_write.name;
  real value, tvalue;
  assign intf_read.value = value;
  assign value = intf_write.value;
  assign intf_read.tvalue = tvalue;
  assign tvalue = intf_write.tvalue;
  always_comb intf_read.handle = intf_write.handle;
  always_comb intf_read.thandle = intf_write.thandle;
  virtual INTF vif_read, vif_write;

  Dummy cl_1, cl_2;

  // Returns a non-null handle
  import "DPI-C" function chandle dpii_handle();

  initial begin

    // Test: no false loop with member-level trigger
    #1ns;
    vif_loop = intf_loop;
    cl_1 = new(vif_loop);
    #1ns;
    src_val = 0;
    #1ns;
    if (!(cl_1.vif.x == 1 && cl_1.vif.y == 0 && cl_1.vif.z == 1 && s1 == 1 && s2 == 1)) $stop;

    // Test: write from module
    #1ns;
    vif_read = intf_read;
    vif_write = intf_write;
    #1ns;
    vif_write.data = 8'hA5;
    #1ns;
    if (vif_read.data !== 8'hA5) $stop;

    // Test: string write from module, then same length with different contents
    vif_write.name = "hello";
    #1ns;
    `checks(vif_read.name, "hello");
    vif_write.name = "world";
    #1ns;
    `checks(vif_read.name, "world");

    // Test: real writes
    vif_write.value = 1.5;
    vif_write.tvalue = 2.5;
    #1ns;
    `checkr(vif_read.value, 1.5);
    `checkr(vif_read.tvalue, 2.5);

    // Test: chandle write, from a non-null handle to null
    vif_write.handle = dpii_handle();
    #1ns;
    if (vif_read.handle == null) `stop;
    vif_write.handle = null;
    #1ns;
    if (vif_read.handle != null) `stop;
    vif_write.thandle = dpii_handle();
    #1ns;
    if (vif_read.thandle == null) `stop;
    vif_write.thandle = null;
    #1ns;
    if (vif_read.thandle != null) `stop;

    // Test: write from class
    #1ns;
    cl_2 = new(vif_write);
    #1ns;
    cl_2.write_data(8'hB7);
    #1ns;
    if (vif_read.data !== 8'hB7) $stop;

    #5ns;
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
