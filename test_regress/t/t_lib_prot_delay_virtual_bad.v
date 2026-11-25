// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// A delay the library may run: in an override of a virtual task it calls
class Base;
  virtual task run();
  endtask
endclass

class Derived extends Base;
  virtual task run();
    #10;
  endtask
endclass

module secret_impl;
  Base b;
  Derived d;
  initial begin
    d = new;
    b = d;
    b.run();
  end
endmodule
