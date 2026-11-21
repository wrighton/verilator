// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

class Outer #(
    int N = 4
);
  class Inner #(
      int M = 1
  );
    static function int f();
      return N * 100 + M;
    endfunction
  endclass
  class TInner #(
      type T = int
  );
    static function int f();
      return $bits(T);
    endfunction
  endclass
endclass

class Leaf;
  static function int f();
    return 1;
  endfunction
endclass

class TypeHolder #(
    type T = int
);
endclass

class Base #(
    type REQ = int
);
endclass

package pkg;
  localparam int PK = 6;
endpackage

module sub #(
    type C,
    int K = 7
);
  // Unsupported: K and PK are not members of a class
  initial $display("%0d", C::Inner#(K)::f());
  initial $display("%0d", C::Inner#(pkg::PK)::f());
endmodule

module sub2;
  class Shadow #(
      type C
  );
    localparam int K = 5;
    static function int f();
      localparam int K = 9;
      // Unsupported: the local K hides the class member K
      return C::Inner#(K)::f();
    endfunction
  endclass

  class ShadowScopes #(
      type C
  );
    localparam logic [6:0] K = 5;
    static function int port(int K);
      // Unsupported: the port K hides the class member K
      return C::TInner#(type (K))::f();
    endfunction
    static function int block();
      begin
        localparam int K = 9;
        // Unsupported: the block's K hides the class member K
        return C::Inner#(K)::f();
      end
    endfunction
    static function int loop();
      int a[1];
      foreach (a[K]) begin
        // Unsupported: the foreach index K hides the class member K
        return C::TInner#(type (K))::f();
      end
      return 0;
    endfunction
    static function int with_arg();
      int q[$] = '{1};
      int r[$];
      // Unsupported: the 'with' argument K hides the class member K
      r = q.find(K) with (C::TInner#(type (K))::f() > 0);
      return r.size();
    endfunction
    static function int enum_item();
      typedef enum int {K = 9} local_e;
      // Unsupported: the enum item K hides the class member K
      return C::Inner#(K)::f();
    endfunction
  endclass

  class MemberTypeParam #(
      type C
  );
    static function int f();
      // Unsupported: parameter values on a type parameter of the scope
      return C::T#(1)::f();
    endfunction
  endclass

  class TypeParamScope #(
      type C
  );
    static function int f();
      // Unsupported: parameter values on a type parameter
      return C#(1)::Inner#(2)::f();
    endfunction
  endclass

  initial $display("%0d", Shadow#(Outer#(3))::f());
  initial $display("%0d", TypeParamScope#(Outer#(4))::f());
  initial $display("%0d", ShadowScopes#(Outer#(3))::port(1));
  initial $display("%0d", ShadowScopes#(Outer#(3))::block());
  initial $display("%0d", ShadowScopes#(Outer#(3))::loop());
  initial $display("%0d", ShadowScopes#(Outer#(3))::with_arg());
  initial $display("%0d", ShadowScopes#(Outer#(3))::enum_item());
  initial $display("%0d", MemberTypeParam#(TypeHolder#(Leaf))::f());
endmodule

module sub3 #(
    type C = Outer#(3)
);
  // Unsupported: parameter values on a type parameter, through its class default
  if (C#(9)::N == 3) begin : g_selected
    initial $display("selected");
  end
  initial $display("%0d", C#(9)::Inner#(1)::f());
endmodule

module t;
  class Derived extends Base #(Outer #(3));
    static function int f();
      // Unsupported: REQ is resolved after parameterization
      return REQ::Inner#(5)::f();
    endfunction
  endclass

  sub #(.C(Outer #(3))) u ();
  sub2 u2 ();
  sub3 u3 ();
  initial $display("%0d", Derived::f());
endmodule
