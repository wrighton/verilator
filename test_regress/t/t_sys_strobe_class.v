// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// $strobe and $monitor of a static property in static methods, and of static members in a
// non-static method
class D;
  int w;
endclass

class C;
  static int v;
  static D other;
  static function int sget();
    return v;
  endfunction
  function void strobe_static();
    $strobe("[%0t] strobe sget=%0d other.w=%0d", $time, sget(), other.w);
  endfunction
  static function void strobe();
    $strobe("[%0t] strobe v=%0d", $time, v);
  endfunction
  static function void monitor();
    $monitor("[%0t] monitor v=%0d", $time, v);
  endfunction
endclass

module t;
  initial begin
    C c;
    C::v = 1;
    C::strobe();
    C::v = 2;  // Displayed at the end of the time step
    #5;
    C::monitor();
    #5;
    C::v = 3;
    #5;
    C::v = 3;  // No change
    #5;
    $monitoroff;
    C::v = 4;
    #5;
    c = new;
    C::other = new;
    C::other.w = 7;
    c.strobe_static();
    C::other.w = 8;  // Displayed at the end of the time step
    #5;
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
