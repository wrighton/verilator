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
  class Mid #(
      int K = 1
  );
    class Leaf #(
        int J = 1
    );
      static function int h();
        return N * 100 + K * 10 + J;
      endfunction
    endclass
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
endclass

class Other;
endclass

class OtherVar;
  static int Inner = 1;
endclass

class OtherTypedef;
  typedef Outer#(5) Inner;
endclass

class OtherQ;
  class Inner #(
      int Q = 1
  );
    static function int f();
      return Q;
    endfunction
  endclass
endclass

class OtherFunc;
  class Inner #(
      int Q = 1
  );
    static function int f();
      return Q;
    endfunction
    static function int M();
      return 2;
    endfunction
  endclass
endclass

class BaseLocal;
  localparam int M = 2;
endclass

class OtherInherited;
  class Inner #(
      int Q = 1
  ) extends BaseLocal;
    static function int f();
      return Q;
    endfunction
  endclass
endclass

class BaseParam #(
    int M = 1
);
endclass

class OtherBaseParam;
  class Inner #(
      int Q = 1
  ) extends BaseParam #(2);
    static function int f();
      return Q;
    endfunction
  endclass
endclass

class OtherEnum;
  class Inner #(
      int Q = 1
  );
    typedef enum {
      M,
      N
    } e_t;
    static function int f();
      return Q;
    endfunction
  endclass
endclass

class OtherTypo;
  class Inner #(
      int WIDTH = 1
  );
    static function int f();
      return WIDTH;
    endfunction
  endclass
endclass

class BaseVarParam #(
    int P = 1
);
  static int M = 3;
endclass

class OtherBaseVar;
  class Inner #(
      int Q = 1
  ) extends BaseVarParam #(2);
    static function int f();
      return Q;
    endfunction
  endclass
endclass

class BaseWidth;
  localparam int WIDTH = 4;
endclass

class OtherTypoInherited;
  class Inner #(
      int Q = 1
  ) extends BaseWidth;
    static function int f();
      return Q;
    endfunction
  endclass
endclass

class OtherDeep;
  class Plain;
    class Deep #(
        int J = 1
    );
      localparam int K = J;
    endclass
  endclass
endclass

class OtherMid;
  class Mid #(
      int Q = 1
  );
    static int K = 3;
  endclass
endclass

class OtherProp;
  class Inner #(
      int Q = 1
  );
    static int M = 2;
    static function int f();
      return Q;
    endfunction
  endclass
endclass

module sub_missing #(
    type C = Outer#(2)
);
  // Bad: Other has no Inner
  initial $display("%0d", C::Inner#(7)::f());
endmodule

module sub_var #(
    type C = Outer#(2)
);
  // Bad: the Inner of OtherVar is not a class
  initial $display("%0d", C::Inner#(7)::f());
endmodule

module sub_typedef #(
    type C = Outer#(2)
);
  // Bad: the Inner of OtherTypedef is a typedef, which takes no parameters
  initial $display("%0d", C::Inner#(7)::f());
endmodule

module sub_prop #(
    type C = Outer#(2)
);
  // Bad: M of the Inner of OtherProp is no parameter
  initial $display("%0d", C::Inner#(.M(7))::f());
endmodule

module sub_pin #(
    type C = Outer#(2)
);
  // Bad: the Inner of OtherQ has no parameter M
  initial $display("%0d", C::Inner#(.M(7))::f());
endmodule

module sub_func #(
    type C = Outer#(2)
);
  // Bad: M of the Inner of OtherFunc is a function
  initial $display("%0d", C::Inner#(.M(7))::f());
endmodule

module sub_inherited #(
    type C = Outer#(2)
);
  // Bad: M of the Inner of OtherInherited is an inherited local parameter
  initial $display("%0d", C::Inner#(.M(7))::f());
endmodule

module sub_base_param #(
    type C = Outer#(2)
);
  // Bad: M is a parameter of the base of the Inner of OtherBaseParam, not of the Inner
  initial $display("%0d", C::Inner#(.M(7))::f());
endmodule

module sub_enum #(
    type C = Outer#(2)
);
  // Bad: M of the Inner of OtherEnum is an enum item
  initial $display("%0d", C::Inner#(.M(7))::f());
endmodule

module sub_typo #(
    type C
);
  // Bad: misspelled parameter
  initial $display("%0d", C::Inner#(.WIDHT(7))::f());
endmodule

module sub_typo_inherited #(
    type C
);
  // Bad: misspelled parameter, close to an inherited local parameter
  initial $display("%0d", C::Inner#(.WIDTX(7))::f());
endmodule

module child #(
    int P = 0
);
  initial $display("%0d", P);
endmodule

module sub_param_value #(
    type C = OtherDeep
);
  // Bad: Other has no Plain, in a parameter value. V3Width then reports the dotted reference,
  // as it does any dotted reference in a parameter value.
  child #(.P(C::Plain::Deep #(7)::K)) u_child ();
endmodule

module sub_base_var #(
    type C = Outer#(2)
);
  // Bad: M is a variable of a base given parameters, which is not searched
  initial $display("%0d", C::Inner#(.M(7))::f());
endmodule

module sub_dup #(
    type C
);
  // Bad: M is set twice
  initial
    $display(
        "%0d",
        C::Inner#(
            .M(7),
            .M(8)
        )::f()
    );
endmodule

module sub_extra #(
    type C
);
  // Bad: Inner has a single parameter
  initial $display("%0d", C::Inner#(7, 8)::f());
endmodule

module sub_mid_prop #(
    type C = Outer#(2)
);
  // Bad: K of the Mid of OtherMid is a variable, so nothing after it is specialized
  initial $display("%0d", C::Mid#(.K(7))::Leaf#(1)::h());
endmodule

module sub_int #(
    type C = Outer#(2)
);
  // Bad: int is not a class
  initial $display("%0d", C::Inner#(7)::f());
endmodule

module sub_chain #(
    type C = Outer#(2)
);
  // Bad: Other has no Plain
  initial $display("%0d", C::Plain::Deep#(7)::h());
endmodule

module sub_mid #(
    type C = Outer#(2)
);
  // Bad: Other has no Mid, so no Leaf in it either, twice
  initial $display("%0d", C::Mid#(4)::Leaf#(1)::h());
  initial $display("%0d", C::Mid#(5)::Leaf#(2)::h());
endmodule

module sub_no_default #(
    type C
);
  // Bad: int is not a class
  initial $display("%0d", C::Inner#(7)::f());
endmodule

module t;
  sub_missing #(.C(Other)) u_missing ();
  sub_var #(.C(OtherVar)) u_var ();
  sub_prop #(.C(OtherProp)) u_prop ();
  sub_typedef #(.C(OtherTypedef)) u_typedef ();
  sub_pin #(.C(OtherQ)) u_pin ();
  sub_func #(.C(OtherFunc)) u_func ();
  sub_inherited #(.C(OtherInherited)) u_inherited ();
  sub_base_param #(.C(OtherBaseParam)) u_base_param ();
  sub_enum #(.C(OtherEnum)) u_enum ();
  sub_typo #(.C(OtherTypo)) u_typo ();
  sub_typo_inherited #(.C(OtherTypoInherited)) u_typo_inherited ();
  sub_param_value #(.C(Other)) u_param_value ();
  sub_base_var #(.C(OtherBaseVar)) u_base_var ();
  sub_dup #(.C(Outer #(3))) u_dup ();
  sub_extra #(.C(Outer #(3))) u_extra ();
  sub_mid_prop #(.C(OtherMid)) u_mid_prop ();
  sub_int #(.C(int)) u_int ();
  sub_chain #(.C(Other)) u_chain ();
  sub_mid #(.C(Other)) u_mid ();
  sub_no_default #(.C(int)) u_no_default ();
  // The template Outer survives as the default specialization
  initial $display("%0d", Outer#()::Inner#(1)::f());
endmodule
