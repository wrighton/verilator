// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// IEEE 1800-2023 26.6: A wildcard export only exports the names its package actually
// imports, that is, references

package p1;
  localparam int W = 6;
  typedef logic [W-1:0] w_t;
  typedef struct packed {logic a;} s_t;
  function automatic int f(int a);
    return a + 1;
  endfunction
  localparam int X = 3;
  localparam int Y = 4;
  localparam int Z = 5;
  class B #(
      type T = int
  );
    T bv;
  endclass
  localparam int UNREF = 9;
  localparam int NAMED = 7;
endpackage

package p2;
  import p1::*;
  export p1::*;
  localparam int D = W * 2;
  function automatic int g();
    return Y;
  endfunction
  class C #(
      int N = 1
  );
    s_t cv;
    function int h();
      return f(X);
    endfunction
  endclass
  class E #(
      type T = int
  ) extends B #(T);
  endclass
  localparam int ZB = $bits(Z);
endpackage

package p3;
  import p2::*;
  export p2::*;
  localparam int D3 = D + Y;
endpackage

package p4;
  import p1::*;
  export *::*;
  export p1::NAMED;
endpackage

package p5;
  import p1::Y;
  export p1::*;
endpackage

module t;
  import p2::*;
  s_t ok_s;
  w_t bad_v;  // <--- Bad: p2 does not reference w_t
  initial begin
    $display("%0d %0d %0d %0d %0d", W, X, Y, Z, f(1));
    $display("%0d", UNREF);  // <--- Bad: p2 does not reference UNREF
  end
endmodule

module t3;
  import p3::*;
  initial begin
    $display("%0d", Y);
    $display("%0d", W);  // <--- Bad: p3 does not reference W
  end
endmodule

module t4;
  import p4::*;
  initial begin
    $display("%0d", NAMED);
    $display("%0d", UNREF);  // <--- Bad: p4 does not reference UNREF
  end
endmodule

module t5;
  import p5::*;
  initial $display("%0d", Y);
endmodule

module t_direct;
  import p2::*;
  import p1::*;
  initial $display("%0d", UNREF);  // Ok, also imported from p1
endmodule

module top;
  t u ();
  t3 u3 ();
  t4 u4 ();
  t5 u5 ();
  t_direct u_direct ();
endmodule
