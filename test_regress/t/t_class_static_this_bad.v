// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

class Cls;
  int x;
  int ok_inst = this.x;  // OK, non-static initializer has an object
  Cls ok_self = this;  // OK, non-static initializer has an object
  static int ok_static = 1;
  static int ok_static2 = ok_static;  // OK, static member
  static int bad_this_member = this.x;  // BAD: no object in static initializer
  static Cls bad_this = this;  // BAD: no object in static initializer
  static int bad_member = x;  // BAD: no object in static initializer
endclass

module t;
  int bad_mod = Cls::x;  // BAD: no object in static initializer
endmodule
