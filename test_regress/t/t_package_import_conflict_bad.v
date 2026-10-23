// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

package p1;
  int x = 1;
  int only1 = 1;
  typedef int t;
  function int f();
    return 1;
  endfunction
endpackage

package p2;
  int x = 2;
  typedef logic t;
  function int f();
    return 2;
  endfunction
endpackage

package p3;
  int y = 3;
endpackage

// Bad: name wildcard imported from two packages and referenced
module amb;
  import p1::*;
  import p2::*;
  int a = x;
  t b;
  initial a = f();
  // OK: only one package defines it
  int c = only1;
endmodule

// Bad: explicit import of a name explicitly imported from another package, or declared in
// the same scope
module expl;
  import p1::x;
  import p2::x;
  int y;
  import p3::y;
endmodule

module expl2;
  import p3::y;
  int y;
endmodule

// Bad: declaration after a reference made the wildcard imported name visible
module late;
  import p3::*;
  int a = y;
  int y;
endmodule

// OK: explicit import or earlier declaration take precedence over wildcard imports
module ok;
  import p1::*;
  import p2::*;
  import p2::x;
  import p2::x;
  int a = x;
  import p3::*;
  int y = 4;
  int b = y;
endmodule

module t;
  amb u_amb ();
  expl u_expl ();
  expl2 u_expl2 ();
  late u_late ();
  ok u_ok ();
endmodule
