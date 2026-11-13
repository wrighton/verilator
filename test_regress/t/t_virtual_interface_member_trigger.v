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
  real_t value;
  chandle_t handle;
  // A static task, so 'path' is a static variable of the interface
  task set_path(input int target);
    string path;
    path = $sformatf("top.m%0d", target);
    name = path;
  endtask
endinterface

class Dummy;
  virtual INTF vif;
  function new(virtual INTF vif);
    this.vif = vif;
  endfunction
  task write_data(logic [7:0] d);
    vif.data = d;
  endtask
  task write_path(int target);
    vif.set_path(target);
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
  str_t name;
  assign intf_read.name = name;
  assign name = intf_write.name;
  real value;
  assign intf_read.value = value;
  assign value = intf_write.value;
  virtual INTF vif_read, vif_write;

  Dummy cl_1, cl_2;

  // Writes from a process woken by an event rather than a delay, so only the
  // virtual interface write triggers re-evaluate the assignments reading them
  event write_ev;
  int write_n;
  always @(write_ev) begin
    if (write_n == 0) vif_write.name = "hello";
    else if (write_n == 1) vif_write.name = "world";
    else if (write_n == 2) cl_2.write_path(12);
    else vif_write.value = 1.5;
  end

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

    // Test: write from class
    #1ns;
    cl_2 = new(vif_write);
    #1ns;
    cl_2.write_data(8'hB7);
    #1ns;
    if (vif_read.data !== 8'hB7) $stop;

    // Test: string write from module, then same length with different contents
    write_n = 0;
    ->write_ev;
    #1ns;
    `checks(vif_read.name, "hello");
    write_n = 1;
    ->write_ev;
    #1ns;
    `checks(vif_read.name, "world");

    // Test: string write by a static task called from class
    write_n = 2;
    ->write_ev;
    #1ns;
    `checks(vif_read.name, "top.m12");

    // Test: real write
    write_n = 3;
    ->write_ev;
    #1ns;
    `checkr(vif_read.value, 1.5);

    // Test: chandle write, which compiles the trigger (no event control or
    // continuous assignment may read a chandle, IEEE 1800-2023 6.14)
    cl_2.vif.handle = null;

    #5ns;
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
