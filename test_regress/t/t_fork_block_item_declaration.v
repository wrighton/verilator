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
