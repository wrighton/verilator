// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

package pkg;
  class POuter #(
      int N = 4
  );
    class PInner #(
        int M = 1
    );
      static function int f();
        return N * 100 + M;
      endfunction
    endclass
  endclass
endpackage

class Glob #(
    int K = 1
);
  class GLeaf #(
      int J = 1
  );
    static function int h();
      return K * 10 + J;
    endfunction
  endclass
endclass

class NonParam;
  class NInner #(
      int M = 1
  );
    static function int f();
      return M * 3;
    endfunction
  endclass
endclass

class BaseNp;
  class BInner #(
      int M = 1
  );
    static function int f();
      return M * 7;
    endfunction
  endclass
endclass

class Derived #(
    int N = 1
) extends BaseNp;
endclass

class NodeA;
  class Node #(
      int M = 1
  );
    static function int f();
      return 1000 + M;
    endfunction
  endclass
endclass

class NodeB;
  class Node #(
      int M = 1
  );
    static function int f();
      return 2000 + M;
    endfunction
  endclass
endclass

class NodeD extends NodeB;
endclass

class NodeShadow extends NodeA;
  class Node #(
      int M = 1
  );
    static function int f();
      return 3000 + M;
    endfunction
  endclass
endclass

class NodeP #(
    int N = 1
);
  class Node #(
      int M = 1
  );
    static function int f();
      return N * 100 + M;
    endfunction
  endclass
endclass

class NodeDP #(
    int K = 1
) extends NodeP #(K * 2);
endclass

class NodeUser #(
    type C = NodeA,
    int M = 5
);
  static function int u();
    return C::Node#(M)::f();
  endfunction
endclass

class NodeUserNoDefault #(
    type C,
    int M = 5
);
  static function int u();
    return C::Node#(M)::f();
  endfunction
endclass

interface class INone;
endclass

interface class INp;
  typedef NonParam np_t;
endclass

interface class IBoth extends INone, INp;
endclass

class UserIBoth #(
    type C = IBoth,
    int M = 4
);
  static function int u();
    return C::np_t::NInner#(M)::f();
  endfunction
endclass

class GlobDeep #(
    int K = 1
);
  class GLeaf #(
      int J = 1
  );
    static function int h();
      return K * 10 + J;
    endfunction
  endclass
endclass

class DeepDefault;
  class Plain;
    class Mid;
      class GLeaf #(
          int J = 1
      );
        static function int h();
          return 900 + J;
        endfunction
      endclass
    endclass
  endclass
endclass

class UserDeep #(
    type C = DeepDefault
);
  static function int u();
    return C::Plain::Mid::GLeaf#(1)::h();
  endfunction
endclass

class DeepTypedef;
  class Plain;
    typedef GlobDeep#(5) Mid;
  endclass
endclass

class TypeInner;
  class Inner #(
      type T = int
  );
    static function int f();
      return $bits(T);
    endfunction
  endclass
endclass

class UserTypeOf #(
    type C
);
  static function int u();
    return C::Inner#(type (7'd0))::f();
  endfunction
endclass

class OtherQ;
  class Inner #(
      type V = int,
      int P = 1
  );
    static function int f();
      return $bits(V) * 10 + P;
    endfunction
  endclass
endclass

class Outer #(
    type T = int,
    int N = 4
);
  class Inner #(
      type U = int,
      int M = 1
  );
    static int s_m = M * 2;
    static function int f();
      return $bits(T) * 10000 + $bits(U) * 100 + N * 10 + M;
    endfunction
  endclass
  class Dep #(
      type U = T,
      int M = N
  );
    static function int f();
      return $bits(U) * 100 + M;
    endfunction
  endclass
  class Base;
    static function int b();
      return $bits(T) * 10 + N;
    endfunction
  endclass
  class Der #(
      int K = 1
  ) extends Base;
    static function int g();
      return b() * 10 + K;
    endfunction
  endclass
  class Plain;
    class Deep #(
        int J = 1
    );
      static function int h();
        return N * 100 + J;
      endfunction
    endclass
  endclass
  class Mid #(
      int L = 1
  );
    class Leaf #(
        int J = 1
    );
      static function int h();
        return N * 100 + L * 10 + J;
      endfunction
    endclass
  endclass
  typedef Glob#(N + 1) glob_t;
  typedef Glob glob1_t;
endclass

class User #(
    type C = Outer#(int, 2)
);
  static function int u();
    return C::Inner#(bit [8:0], 4)::f();
  endfunction
endclass

class UserGlob #(
    type C = Outer#(int, 3)
);
  static function int u();
    return C::glob_t::GLeaf#(9)::h();
  endfunction
endclass

class UserPos #(
    type C = Outer#(int, 2)
);
  static function int u();
    return C::Inner#(byte, 6)::f();
  endfunction
endclass

typedef Outer#(bit [14:0], 6) o15_t;

module sub #(
    type C = Outer#(int, 2),
    int K = 1
);
  initial begin
    `checkd(C::Inner#(bit [10:0], 8)::f(), 81178);
    `checkd(Outer#(bit [4:0], K)::Inner#(byte, 9)::f(), 50869);
  end
endmodule

module t;
  sub #(
      .C(Outer #(byte, 7)),
      .K(6)
  ) u_sub ();

  initial begin
    `checkd(Outer#(byte, 3)::Inner#(shortint, 5)::f(), 81635);
    `checkd(Outer#(bit [6:0], 2)::Inner#(byte, 7)::f(), 70827);
    `checkd(Outer#(byte, 3)::Inner#(shortint, 5)::s_m, 10);
    `checkd(Outer#(byte, 3)::Inner#()::f(), 83231);
    `checkd(Outer#(bit [6:0], 2)::Inner#(shortint)::f(), 71621);
    `checkd(Outer#(byte, 3)::Dep#()::f(), 803);
    `checkd(Outer#(byte, 3)::Der#(4)::g(), 834);
    `checkd(Outer#(bit [6:0], 2)::Der#(9)::g(), 729);
    `checkd(o15_t::Inner#(bit [32:0], 3)::f(), 153363);
    `checkd(Outer#(byte, 3)::Mid#(2)::Leaf#(7)::h(), 327);
    `checkd(Outer#(byte, 5)::Mid#(4)::Leaf#(1)::h(), 541);
    `checkd(Outer#(byte, 3)::Plain::Deep#(7)::h(), 307);
    `checkd(Outer#(bit [6:0], 2)::glob_t::GLeaf#(9)::h(), 39);
    `checkd(pkg::POuter#(3)::PInner#(6)::f(), 306);
    `checkd(User#(Outer#(byte, 6))::u(), 80964);
    `checkd(UserPos#(OtherQ)::u(), 86);
    `checkd(NonParam::NInner#(5)::f(), 15);
    `checkd(Derived#(2)::BInner#(3)::f(), 21);
    `checkd(Outer#(byte, 3)::glob1_t::GLeaf#(4)::h(), 14);
    `checkd(NodeUser#()::u(), 1005);
    `checkd(NodeUser#(NodeD, 1)::u(), 2001);
    `checkd(NodeUser#(NodeShadow, 2)::u(), 3002);
    `checkd(NodeUser#(NodeDP#(4), 7)::u(), 807);
    `checkd(NodeUserNoDefault#(NodeDP#(3), 6)::u(), 606);
    `checkd(IBoth::np_t::NInner#(2)::f(), 6);
    `checkd(UserIBoth#()::u(), 12);
    `checkd(UserGlob#(Outer#(bit [6:0], 2))::u(), 39);
    `checkd(UserDeep#(DeepTypedef)::u(), 51);
    `checkd(UserTypeOf#(TypeInner)::u(), 7);
    #1;
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
