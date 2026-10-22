// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;
  class Base;
  endclass
  class Derived extends Base;
  endclass
  class Other;
  endclass

  int m[Base];
  int n[int];
  int k[Derived];
  Base b;
  Derived d;
  Other o;

  initial begin
    // Legal
    m[d] = 1;
    m[null] = 2;
    if (m.exists(d)) m.delete(d);
    void'(k.first(b));  // Writes a Derived index into a Base variable
    // Illegal, index not assignment compatible
    m[o] = 3;
    if (m.exists(o)) $stop;
    m.delete(o);
    void'(m.first(o));
    void'(m.last(d));  // Would write a Base index into a Derived variable
    n[o] = 4;
  end
endmodule
