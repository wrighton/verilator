// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2023 Antmicro Ltd
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define checks(gotv,expv) do if ((gotv) != (expv)) begin $write("%%Error: %s:%0d:  got='%s' exp='%s'\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

static int counts[10];

class Foo;
  static int last;

  static task do_something();
    for (int i = 0; i < 10; i++)
      frk :
      fork
        int ii = i;
        #(10 + i) begin
          $display("i: %d, ii: %d", i, ii);
          if (counts[ii]++ != 0) $stop;
        end
      join_none : frk
    #1;
  endtask

  // Typedefs in the declarations of a fork in a class method
  static task typedefs(int i);
    fork
      typedef enum int {
        E_A = 3,
        E_B = 7
      } e_t /*verilator public*/;
      typedef struct {
        int x;
        e_t e;
      } s_t;
      typedef int arr_t[2];
      s_t s = '{0, E_B};
      arr_t a;
      begin
        #1 a[1] = i + int'(s.e);
        last = a[1];
      end
    join_none
  endtask

  // Scope name inside forks with declarations in a class method
  static string base;
  static task scopes();
    base = $sformatf("%m");
    fork : cj
      automatic int a = 1;
      #1 `checks($sformatf("%m"), {base, ".cj"});
    join
    fork : cn
      automatic int a = 1;
      #1 `checks($sformatf("%m"), {base, ".cn"});
    join_none
    #2;
  endtask
endclass

module t;
  int v;
  int o_task;

  // Instance, functions and their typedefs after a named fork directly under an initial
  int o_named;
  initial
    fork : f
      #1 o_named = 1;
    join
  sub u ();
  function automatic string scope_func();
    return $sformatf("%m");
  endfunction
  function automatic int typedef_a(int i);
    typedef int a_t;
    a_t a = i + 1;
    return a;
  endfunction
  function automatic int typedef_b(int i);
    typedef int b_t;
    b_t b = i + 2;
    return b;
  endfunction
  initial begin
    #2 `checkd(o_named, 1);
    `checks($sformatf("%m"), "t");
    `checks(scope_func(), "t.scope_func");
    `checkd(typedef_a(o_named), 2);
    `checkd(typedef_b(o_named), 3);
  end

  // Typedefs in the declarations of a fork in a task
  task automatic typedefs(int i);
    fork
      typedef enum int {
        E_A = 3,
        E_B = 7
      } e_t;
      typedef e_t arr_t[2];
      arr_t a;
      begin
        #1 a[1] = E_B;
        o_task = i + int'(a[1]);
      end
    join_any
  endtask

  // Unpacked struct typedef in the declarations of a fork in a task
  task automatic struct_typedefs(int i);
    fork
      typedef enum int {
        E_A = 3,
        E_B = 7
      } e_t /*verilator public*/;
      typedef struct {
        int x;
        e_t e;
      } s_t;
      s_t s[2];
      begin
        #1 s[1].e = E_B;
        o_task = i + int'(s[1].e) + 1;
      end
    join_none
  endtask

  // Scope name after forks in a static task
  task static scope_names();
    fork
      int a = 1;
      #1 o_task = a;
    join
    `checks($sformatf("%m"), "t.scope_names");
    fork : named_fork
      #1 o_task = 2;
    join_none
    `checks($sformatf("%m"), "t.scope_names");
  endtask

  // Scope name inside forks with automatic declarations
  function automatic string scope_up(string s);
    for (int i = s.len() - 1; i >= 0; --i) if (s[i] == ".") return s.substr(0, i - 1);
    return "";
  endfunction
  task automatic auto_scopes();
    fork : tn
      automatic int a = 1;
      #1 `checks($sformatf("%m"), "t.auto_scopes.tn");
    join_none
    fork
      automatic int a = 1;
      #1 `checks(scope_up($sformatf("%m")), "t.auto_scopes");
    join_any
    #2;
  endtask
  initial begin : wrapped
    int o;
    fork : fj
      automatic int a = 1;
      begin
        #1 o = a;
        `checks($sformatf("%m"), "t.wrapped.fj");
      end
    join
    `checkd(o, 1);
    fork : fa
      automatic int a = 2;
      #1 `checks($sformatf("%m"), "t.wrapped.fa");
    join_any
    fork : fn
      automatic int a = 3;
      #1 `checks($sformatf("%m"), "t.wrapped.fn");
    join_none
    #2;
    fork
      automatic int a = 4;
      begin
        #1 o = a;
        `checks(scope_up($sformatf("%m")), "t.wrapped");
      end
    join
    `checkd(o, 4);
    fork : no
      automatic int a = 5;
      fork : ni
        automatic int b = 6;
        begin
          #1 o = a + b;
          `checks($sformatf("%m"), "t.wrapped.no.ni");
        end
      join
    join
    `checkd(o, 11);
    fork : sf
      automatic int a = 7;
      static int cs = 8;
      #1 cs = cs + a;
    join
    `checkd(wrapped.sf.cs, 15);
    `checks($sformatf("%m"), "t.wrapped");
    auto_scopes();
    Foo::scopes();
  end

  initial begin : main
    automatic int desired_counts[10] = '{10{1}};
    int o;
    counts = '{10{0}};
    v = 5;

    Foo::do_something();
    #20;

    if (counts != desired_counts) $stop;

    // Scope name after forks with declarations, of each join type
    fork
      int a;
      begin
        a = v;
        #1 o = a;
      end
    join
    `checkd(o, 5);
    `checks($sformatf("%m"), "t.main");
    fork
      int a;
      begin
        a = v + 1;
        #1 o = a;
      end
    join_any
    `checkd(o, 6);
    `checks($sformatf("%m"), "t.main");
    fork
      int a;
      begin
        a = v + 2;
        #1 o = a;
      end
    join_none
    `checks($sformatf("%m"), "t.main");
    #2;
    `checkd(o, 7);

    // Typedefs in the declarations of forks, of each join type
    fork
      typedef struct {
        int x;
        int y;
      } s_t;
      s_t s[2];
      begin
        #1 s[1].y = v;
        o = s[1].y;
      end
    join
    `checkd(o, 5);
    fork
      typedef enum int {
        E_A = 3,
        E_B = 7
      } s_t;
      s_t e;
      begin
        #1 e = E_B;
        o = v + int'(e);
      end
    join_any
    `checkd(o, 12);
    fork
      typedef int s_t[3];
      s_t a;
      begin
        #1 a[2] = v + 1;
        o = a[2];
      end
    join_none
    #2;
    `checkd(o, 6);

    // Nested and named forks
    fork : outer
      static int a = 1;
      begin
        fork
          automatic int b = 2;
          #1 o = a + b;
        join
        `checks($sformatf("%m"), "t.main.outer");
      end
    join
    `checkd(o, 3);
    `checks($sformatf("%m"), "t.main");
    fork : later
      `checks($sformatf("%m"), "t.main.later");
    join

    typedefs(v);
    `checkd(o_task, 12);
    struct_typedefs(v);
    #2;
    `checkd(o_task, 13);
    Foo::typedefs(v);
    #2;
    `checkd(Foo::last, 12);
    scope_names();
    `checkd(o_task, 1);
    #2;
    `checkd(o_task, 2);

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule

module sub;
  initial #2 `checks($sformatf("%m"), "t.u");
endmodule
