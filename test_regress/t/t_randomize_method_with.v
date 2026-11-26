// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2024 Antmicro Ltd
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

`define check_rand(cl, field) \
begin \
   automatic longint prev_result; \
   automatic int ok; \
   void'(cl.randomize()); \
   prev_result = longint'(field); \
   repeat(9) begin \
      longint result; \
      void'(cl.randomize()); \
      result = longint'(field); \
      if (result != prev_result) ok = 1; \
      prev_result = result; \
   end \
   if (ok != 1) $stop; \
end

class Boo;
  function new();
    boo = 6;
  endfunction

  int unsigned boo;
endclass

class Foo extends Boo;
  rand int unsigned a;
  rand int unsigned b;
  int x;

  function new(int x);
    this.x = x;
  endfunction

  constraint constr1_c { b < x; }
  function bit test_this_randomize;
    return this.randomize() with { a <= boo; } == 1;
  endfunction
endclass

// Current AstWith representation makes VARs of caller indistinguishable from VARs of randomized
// object if both the caller and callee are the same module, but different instances.
// That's why for the purpose of this test, the caller derives a different class
class Bar extends Boo;
  // Give the local variables a different scope by defining the functino under Bar
  static function bit test_local_constrdep(Foo foo, int c);
    return foo.randomize() with { a <= c; a > 1; x % a == 0; } == 1;
  endfunction

  function bit test_capture_of_callers_derived_var(Foo foo);
    boo = 4;
    foo.a = 3;
    return (foo.randomize() with { a == local::boo; } == 1) && (foo.a == 4);
  endfunction

  static function bit test_capture_of_callees_derived_var(Foo foo);
    foo.a = 5;
    return (foo.randomize() with { a == boo; } == 1) && (foo.a == 6);
  endfunction

  static function bit test_capture_of_local_qualifier(Foo foo);
    foo.a = 5;
    return (foo.randomize() with { a == boo; } == 1) && (foo.a == 6);
  endfunction
endclass

class Baz;
  rand int v;
endclass

class Baz2;
  rand int v;
  function bit test_this_randomize;
    return this.randomize() with { v == 5; } == 1;
  endfunction
  function bit test_randomize_noparen;
    return randomize with { v == 6; } == 1 && v == 6;
  endfunction
  function bit test_this_randomize_noparen;
    return this.randomize with { v == 7; } == 1 && v == 7;
  endfunction
endclass

module submodule();
  int sub_var = 7;
endmodule

function automatic int return_2();
  return 2;
endfunction

class Cls;
  rand int a;
  rand int b;
endclass

class Cls2 extends Cls;
  rand int c;
endclass

class StaticRandCls;
  static rand int s;
endclass

class StaticOwnCls;
  static rand bit [6:0] s;
  rand bit [6:0] x;
  constraint keep_s {s == 45;}
endclass

class StaticOwnDerived extends StaticOwnCls;
endclass

class StaticBareCls;
  static rand bit [6:0] s;
  rand bit [6:0] x;
endclass

class StaticBareDerived extends StaticBareCls;
endclass

// Not reaching a StaticRandCls through rand class handles, so StaticRandCls::s is a state value
class StaticRandUser;
  rand int v;
  function bit test_static_of_other_class();
    StaticRandCls::s = 60;
    return randomize() with {v == StaticRandCls::s;} == 1 && v == 60;
  endfunction
endclass

class NoParen;
  int a = 4;  // Not rand, so constraints only read it
  rand int b;
endclass

module mwith ();
  submodule sub1 ();
  submodule sub2 ();

  function automatic int return_3();
    return 3;
  endfunction

  initial begin
    automatic int c = 30;
    automatic Foo foo = new(c);
    automatic Baz baz = new;
    typedef Baz baz_t;
    automatic baz_t baz1 = new;
    automatic Baz2 baz2 = new;
    automatic Bar bar = new;
    automatic Cls2 cls2 = new;
    automatic Cls cls = cls2;

    $display("foo.x = %d", foo.x);
    $display("-----------------");

    repeat (20) begin
      if (Bar::test_local_constrdep(foo, 5)) begin
        $display("foo.a = %d", foo.a);
        $display("foo.b = %d", foo.b);
        $display("-----------------");

        if (!(foo.a inside {2, 3, 5})) $stop;
        if (foo.b >= foo.x) $stop;
        if (foo.a > c) $stop;
        if (foo.a <= 1) $stop;

        sub1.sub_var = foo.a;
      end
      else $display("Failed to randomize foo with inline constraints");
    end

    if (cls.randomize() with {b == 1;} != 1) $stop;
    if (cls.b != 1) $stop;
    `check_rand(cls2, cls2.a);
    `check_rand(cls2, cls2.c);

    // Check randomize as a task
    // verilator lint_off IGNOREDRETURN
    cls.randomize() with {b == 2;};
    // verilator lint_on IGNOREDRETURN
    if (cls.b != 2) $stop;

    // Check randomize without parentheses
    if (cls.randomize with {b == 3;} != 1) $stop;
    if (cls.b != 3) $stop;
    if (cls.randomize with (b) {b == 4;} != 1) $stop;
    if (cls.b != 4) $stop;
    // verilator lint_off IGNOREDRETURN
    cls.randomize with {b == 5;};
    if (cls.b != 5) $stop;
    cls.randomize with (b) {b == 6;};
    // verilator lint_on IGNOREDRETURN
    if (cls.b != 6) $stop;
    if (!baz2.test_randomize_noparen()) $stop;

    // Check capture of a static variable
    if (foo.randomize() with {a > sub1.sub_var;} != 1) $stop;
    // Check reference to a function
    if (foo.randomize() with {a > return_2();} != 1) $stop;
    // Check randomization of class with no constraints
    if (baz.randomize() with {v inside {[2 : 10]};} != 1) $stop;
    if (baz1.randomize() with {v inside {[2 : 10]};} != 1) $stop;
    // Check randomization with captured non-static variable from different AstNodeModule
    if (!bar.test_capture_of_callers_derived_var(foo)) $stop;
    // Check randomization with non-captured non-static variable from different AstNodeModule
    if (!Bar::test_capture_of_callees_derived_var(foo)) $stop;
    // Check this.randomize()
    if (!foo.test_this_randomize()) $stop;
    // Check this.randomize() with no constraints
    if (!baz2.test_this_randomize()) $stop;

    // Check a static rand member of another class, a state value of the caller
    begin
      automatic StaticRandUser su = new;
      int randomize_result;
      StaticRandCls::s = 50;
      randomize_result = su.randomize() with {v == StaticRandCls::s;};
      `checkd(randomize_result, 1);
      `checkd(su.v, 50);
      randomize_result = su.randomize() with {StaticRandCls::s == 3;};
      `checkd(randomize_result, 0);
      `checkd(StaticRandCls::s, 50);
      `checkd(su.test_static_of_other_class(), 1'b1);
    end

    // Check a static rand member of the randomized object's class, a random variable
    begin
      automatic StaticOwnDerived so = new;
      int randomize_result;
      StaticOwnCls::s = 11;
      randomize_result = so.randomize() with {s == 45; x == s;};
      `checkd(randomize_result, 1);
      `checkd(StaticOwnCls::s, 45);
      `checkd(so.x, 45);
      StaticOwnCls::s = 11;
      so.x = 0;
      randomize_result = so.randomize() with {StaticOwnCls::s == 45; x == StaticOwnCls::s;};
      `checkd(randomize_result, 1);
      `checkd(StaticOwnCls::s, 45);
      `checkd(so.x, 45);
    end
    begin
      automatic StaticBareCls sb = new;
      automatic StaticBareDerived sd = new;
      int randomize_result;
      randomize_result = sb.randomize() with {StaticBareCls::s == 8;};
      `checkd(randomize_result, 1);
      `checkd(StaticBareCls::s, 8);
      randomize_result = sd.randomize() with {StaticBareCls::s == 9;};
      `checkd(randomize_result, 1);
      `checkd(StaticBareCls::s, 9);
      randomize_result = sb.randomize() with {sb.s == 14;};
      `checkd(randomize_result, 1);
      `checkd(StaticBareCls::s, 14);
      repeat (10) begin
        randomize_result = sb.randomize() with {s inside {[1 : 9]};};
        `checkd(randomize_result, 1);
        `checkd(StaticBareCls::s inside {[1 : 9]}, 1);
      end
    end

    // Check randomize with a constraint block and no argument parentheses
    begin
      automatic NoParen np = new;
      automatic int a = 7;  // Same name as a member of NoParen
      int randomize_result;
      bit test_result;
      randomize_result = np.randomize with {b == a;};
      `checkd(randomize_result, 1);
      `checkd(np.b, 4);  // Unrestricted: 'a' is the member
      randomize_result = np.randomize with (b) {b == a;};
      `checkd(randomize_result, 1);
      `checkd(np.b, 7);  // Restricted: 'a' is the caller's variable
      randomize_result = np.randomize with () {np.b == a + 1;};
      `checkd(randomize_result, 1);
      `checkd(np.b, 8);
      np.randomize with {b == 9;};
      `checkd(np.b, 9);
      np.randomize with (b) {b == a + 3;};
      `checkd(np.b, 10);
      void'(np.randomize with (b) {b == a + 4;});
      `checkd(np.b, 11);
      test_result = baz2.test_randomize_noparen();
      `checkd(test_result, 1'b1);
      test_result = baz2.test_this_randomize_noparen();
      `checkd(test_result, 1'b1);
    end

    $write("*-* All Finished *-*\n");
    $finish();
  end
endmodule
