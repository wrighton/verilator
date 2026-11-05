// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define checks(gotv,expv) do if ((gotv) != (expv)) begin $write("%%Error: %s:%0d:  got='%s' exp='%s'\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

package pkg;
  function automatic int pkg_f(int x);
    typedef struct {int unsigned v;} s_t;
    s_t a[2];
    a[1] = '{x};
    return a[1].v;
  endfunction
endpackage

interface ifc;
  function automatic int ifc_f(int x);
    typedef struct {int unsigned v;} s_t;
    s_t a[2];
    a[0] = '{x + 1};
    return a[0].v;
  endfunction
endinterface

class Cls;
  task run(int x);
    typedef struct {
      int unsigned v;
      string s;
    } s_t;
    s_t a[2];
    a[1] = '{x, "cls"};
    `checkd(a[1].v, x);
    `checks(a[1].s, "cls");
  endtask
  static function int sf(int x);
    typedef struct {int unsigned v;} s_t;
    s_t q[$];
    q.push_back('{x + 2});
    return q[0].v;
  endfunction
endclass

class ParamCls #(
    int N = 1
);
  static function int pf(int x);
    typedef struct {int unsigned v;} s_t;
    s_t a[N];
    a[N-1] = '{x + N};
    return a[N-1].v;
  endfunction
endclass

module t;
  int base;

  // Reporter's case: unpacked struct typedef in a task, used as array element type
  task automatic run_int(int x);
    typedef struct {int unsigned v;} cls_t;
    cls_t c[2];
    c[0] = '{x};
    `checkd(c[0].v, x);
  endtask
  // Reporter's case: same with a string member
  task automatic run_str(int x);
    typedef struct {
      string name;
      int unsigned v;
    } cls_t;
    cls_t c[2];
    c[0] = '{"a", x};
    c[1] = '{"b", 2};
    `checkd(c[0].v + c[1].v, x + 2);
    `checks(c[1].name, "b");
  endtask
  initial begin
    #1;
    base = $urandom_range(10, 100);
    run_int(base);
    run_str(base);
  end

  // Function, scalar, and typedef in a named block inside a task
  function automatic int func_local(int x);
    typedef struct {int unsigned v;} s_t;
    s_t a[2];
    s_t s;
    a = '{'{x}, '{x + 1}};
    s = '{x};
    return a[0].v + a[1].v + s.v;
  endfunction
  task automatic named_local(int x);
    begin : blk
      typedef struct {int unsigned v;} s_t;
      s_t a[2];
      a[1] = '{x};
      `checkd(a[1].v, x);
    end
  endtask
  initial begin
    #2;
    `checkd(func_local(base), 3 * base + 1);
    named_local(base);
  end

  // Containers, typedef chains, packed struct, union and enum element types
  task automatic kinds(int x);
    typedef struct {int unsigned v;} s_t;
    typedef s_t s2_t;
    typedef union {
      int unsigned i;
      bit [31:0] b;
    } u_t;
    typedef enum {E0, E1, E2} e_t;
    typedef struct packed {logic [6:0] x;} p_t;
    s_t q[$];
    s2_t d[];
    s2_t sa[2];
    s_t aa[string];
    u_t ua[2];
    e_t ea[3];
    p_t pa[2];
    q.push_back('{x});
    d = new[2];
    d[1] = '{x + 1};
    sa[0] = '{x + 2};
    aa["k"] = '{x + 3};
    ua[1].i = x + 4;
    ea[2] = e_t'(x % 3);
    pa[1] = '{x[6:0]};
    `checkd(q[0].v, x);
    `checkd(d[1].v, x + 1);
    `checkd(sa[0].v, x + 2);
    `checkd(aa["k"].v, x + 3);
    `checkd(ua[1].b, x + 4);
    `checkd(int'(ea[2]), x % 3);
    `checkd(pa[1].x, x[6:0]);
  endtask
  initial begin
    #3;
    kinds(base);
  end

  // Same typedef names in two tasks, including public enums
  task automatic same_a(int x);
    typedef struct {int unsigned v;} s_t;
    typedef enum {A0, A1} e_t  /*verilator public*/;
    s_t a[2];
    e_t e[2];
    a[1] = '{x};
    e[1] = e_t'(x % 2);
    `checkd(a[1].v, x);
    `checkd(int'(e[1]), x % 2);
  endtask
  task automatic same_b(int x);
    typedef struct {string s;} s_t;
    typedef enum {B0, B1, B2} e_t  /*verilator public*/;
    s_t a[2];
    e_t e[2];
    a[1] = '{$sformatf("%0d", x)};
    e[1] = e_t'(x % 3);
    `checks(a[1].s, $sformatf("%0d", x));
    `checkd(int'(e[1]), x % 3);
  endtask
  initial begin
    #4;
    same_a(base);
    same_b(base);
  end

  // Typedef in a fork in a task, and in a task in a generate block
  task automatic forked(int x, output int o);
    fork
      begin
        typedef struct {int unsigned v;} s_t;
        s_t a[2];
        #1 a[1] = '{x};
        o = a[1].v;
      end
    join
  endtask
  for (genvar g = 0; g < 2; ++g) begin : gen
    function automatic int gen_f(int x);
      typedef struct {int unsigned v;} s_t;
      s_t a[2];
      a[1] = '{x + g};
      return a[1].v;
    endfunction
  end
  initial begin
    int o;
    #5;
    forked(base, o);
    `checkd(o, base);
    `checkd(gen[1].gen_f(base), base + 1);
  end

  // Package, interface and class methods
  ifc i ();
  initial begin
    automatic Cls c = new;
    #10;
    `checkd(pkg::pkg_f(base), base);
    `checkd(i.ifc_f(base), base + 1);
    c.run(base);
    `checkd(Cls::sf(base), base + 2);
    `checkd(ParamCls#(2)::pf(base), base + 2);
    `checkd(ParamCls#(1)::pf(base), base + 1);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
