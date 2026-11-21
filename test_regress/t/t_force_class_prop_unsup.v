// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// A force keeps reading its value after the force statement, but the value is captured
// outside the class, where the object of the enclosing method is not known

interface prop_force_if;
  logic [7:0] sig;
endinterface

class Nested;
  logic [7:0] m_deep;
endclass

class DriverBase;
  logic [7:0] m_base;
endclass

class Driver extends DriverBase;
  logic [7:0] m_val;
  virtual prop_force_if m_vif;
  Nested m_nested;
  task from_value();
    force t.y = m_val;  // Error: a property of this object
  endtask
  task from_vif();
    force t.y = m_vif.sig;  // Error: a signal through a property handle
  endtask
  task from_nested();
    force t.y = m_nested.m_deep;  // Error: a property of a property's object
  endtask
  task from_this();
    force t.y = this.m_val;  // Error: a property named through 'this'
  endtask
  task from_super();
    force t.y = super.m_base;  // Error: a property of the base class
  endtask
  task from_dead_arm();
    // Error: the check runs before constant folding, so an arm never selected counts too
    force t.y = 1'b0 ? m_val : t.src;
  endtask
endclass

module t;
  logic [7:0] y;
  logic [7:0] src;
  prop_force_if i ();

  initial begin
    automatic Driver d = new;
    d.m_vif = i;
    d.m_nested = new;
    d.from_value();
    d.from_vif();
    d.from_nested();
    d.from_this();
    d.from_super();
    d.from_dead_arm();
  end
endmodule
