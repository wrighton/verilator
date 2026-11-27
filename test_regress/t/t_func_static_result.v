// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

typedef int q_t[$];
typedef enum int {
  E0 = 0,
  E9 = 9
} e_t;

// The result variable of a static function is static, so keeps its value between calls,
// that of an automatic function does not (IEEE 1800-2023 13.4.1, 13.4.2)

class Cls;
  // Class methods are automatic
  function int meth();
    meth = meth + 1;
  endfunction
endclass

module auto_mod;
  // Functions in an automatic module are automatic
  function automatic int fa();
    fa = fa + 1;
  endfunction
  function int count2();
    int a;
    a = fa();
    return fa() + a;
  endfunction
endmodule

module t;
  function static int g_static();
    g_static = g_static + 1;
  endfunction
  // Static by the module's default lifetime
  function int g_default();
    g_default = g_default + 1;
  endfunction
  function automatic int g_auto();
    g_auto = g_auto + 1;
  endfunction
  function static logic [3:0] g_part(int i);
    g_part[i] = 1'b1;
  endfunction
  function static int g_inc();
    g_inc++;
  endfunction
  function static int g_compound();
    g_compound += 2;
  endfunction
  function static int g_return(int v);
    g_return = g_return + v;
    return g_return;
  endfunction
  // Not written by every call, so returns the previous call's value when not
  function static int g_cond(bit c);
    if (c) g_cond = 7;
  endfunction
  function static int g_case(int k);
    case (k)
      1: g_case = 10;
      2: g_case = 20;
    endcase
  endfunction
  function static int g_loop(int n);
    for (int i = 0; i < n; i++) g_loop = i + 100;
  endfunction
  function static int g_disable(bit c);
    begin : blk
      if (c) disable blk;
      g_disable = 3;
    end
  endfunction
  // Written by a system function or method
  function static int g_sscanf(bit c);
    if (c) void'($sscanf("77", "%d", g_sscanf));
  endfunction
  function static e_t g_cast(bit c);
    if (c) void'($cast(g_cast, 9));
  endfunction
  function static q_t g_queue();
    g_queue.push_back(1);
  endfunction
  // A variable of the same name in a block is another variable
  function static int g_shadow(bit c);
    begin : b
      int g_shadow;
      g_shadow = 1;
    end
    if (c) g_shadow = 7;
  endfunction
  // An exit before the assignment returns a value, as a 'return' without one is illegal in a
  // function with a result (IEEE 1800-2023 13.4.1), so no different
  function static int g_early(bit w);
    if (w) return 9;
    g_early = 5;
  endfunction
  // Always written first, so no different
  function static int g_written(int v);
    g_written = v * 2;
  endfunction
  function static int g_returned(int v);
    return v + 1;
  endfunction

  auto_mod u_auto ();
  Cls c;
  q_t q;

  initial begin
    `checkd(g_static(), 1);
    `checkd(g_static(), 2);
    `checkd(g_static(), 3);
    `checkd(g_default(), 1);
    `checkd(g_default(), 2);
    `checkd(g_auto(), 1);
    `checkd(g_auto(), 1);
    `checkd(g_part(0), 4'b0001);
    `checkd(g_part(2), 4'b0101);
    `checkd(g_inc(), 1);
    `checkd(g_inc(), 2);
    `checkd(g_compound(), 2);
    `checkd(g_compound(), 4);
    `checkd(g_return(5), 5);
    `checkd(g_return(6), 11);
    `checkd(g_cond(1), 7);
    `checkd(g_cond(0), 7);
    `checkd(g_case(2), 20);
    `checkd(g_case(3), 20);
    `checkd(g_loop(2), 101);
    `checkd(g_loop(0), 101);
    `checkd(g_disable(0), 3);
    `checkd(g_disable(1), 3);
    `checkd(g_sscanf(1), 77);
    `checkd(g_sscanf(0), 77);
    `checkd(g_cast(1), E9);
    `checkd(g_cast(0), E9);
    q = g_queue();
    q = g_queue();
    `checkd(q.size(), 2);
    `checkd(g_shadow(1), 7);
    `checkd(g_shadow(0), 7);
    `checkd(g_early(1), 9);
    `checkd(g_early(0), 5);
    `checkd(g_returned(1), 2);
    `checkd(g_written(3), 6);
    `checkd(g_written(4), 8);
    `checkd(u_auto.count2(), 2);
    c = new;
    `checkd(c.meth(), 1);
    `checkd(c.meth(), 1);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
