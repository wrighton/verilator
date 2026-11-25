// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Michael Wrighton
// SPDX-License-Identifier: CC0-1.0

// Upwards calls to tasks and functions of a module specialized several ways

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module t (
    input clk
);
  int cyc = 0;

  // Test: calls by module name, from a module shared by two specializations
  mid #(.SCALE(3)) m3 ();
  mid #(.SCALE(5)) m5 ();
  always @(posedge clk) begin
    if (cyc == 1) begin
      `checkd(m3.l.func, 3);
      `checkd(m5.l.func, 5);
      `checkd(m3.l.arg, 12);
      `checkd(m5.l.arg, 20);
      `checkd(m3.l.named, 15);
      `checkd(m5.l.named, 25);
      `checkd(m3.l.task_out, 6);
      `checkd(m5.l.task_out, 10);
      `checkd(m3.l.color, 0);
      `checkd(m5.l.color, 1);
    end
  end

  // Test: call by instance name
  wrap #(.SCALE(3)) w3 ();
  wrap #(.SCALE(5)) w5 ();
  always @(posedge clk) begin
    if (cyc == 1) begin
      `checkd(w3.r.func, 3);
      `checkd(w5.r.func, 5);
    end
  end

  // Test: specializations from a generate loop
  for (genvar i = 1; i <= 3; ++i) begin : g
    mid #(.SCALE(i)) m ();
  end
  always @(posedge clk) begin
    if (cyc == 1) begin
      `checkd(g[1].m.l.func, 1);
      `checkd(g[2].m.l.func, 2);
      `checkd(g[3].m.l.func, 3);
    end
  end

  // Test: one call resolving to the generate blocks of two different parent modules
  parent_a pa ();
  parent_b pb ();
  always @(posedge clk) begin
    if (cyc == 1) begin
      `checkd(pa.c.func, 1);
      `checkd(pb.c.func, 2);
    end
  end

  // Test: a default argument value, the same in each specialization, which a local call
  // also keeps
  defaults #(.P(1)) d1 ();
  defaults #(.P(2)) d2 ();
  defaults #(.P(2)) d2b ();
  always @(posedge clk) begin
    if (cyc == 1) begin
      `checkd(d1.r.defaulted, 3);
      `checkd(d2.r.defaulted, 3);
      `checkd(d2b.r.defaulted, 3);
      `checkd(d1.local_call, 4);
      `checkd(d2.local_call, 5);
      `checkd(d1.r.supplied, 37);
      `checkd(d2.r.supplied, 37);
      `checkd(d2b.r.supplied, 37);
    end
  end

  // Test: defaults of an unrelated function of the same name do not matter
  unrelated un ();
  always @(posedge clk) begin
    if (cyc == 1) `checkd(un.direct, 77);
  end

  // Test: a default argument value, the same as the instances are of one module
  plain p1 ();
  plain p2 ();
  same_spec #(.P(4)) s1 ();
  same_spec #(.P(4)) s2 ();
  always @(posedge clk) begin
    if (cyc == 1) begin
      `checkd(p1.r.got, 42);
      `checkd(p2.r.got, 42);
      `checkd(s1.r.got, 400);
      `checkd(s2.r.got, 400);
      `checkd(s1.r.named, 405);
      `checkd(s2.r.named, 405);
    end
  end

  always @(posedge clk) begin
    cyc <= cyc + 1;
    if (cyc == 2) begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule

module mid #(
    parameter int SCALE = 1
);
  function automatic int f();
    return SCALE;
  endfunction
  function automatic int g(int a);
    return a * SCALE;
  endfunction
  task automatic t(output int o);
    o = SCALE * 2;
  endtask
  // Each specialization has its own copy of this enum type
  typedef enum int {
    RED,
    GREEN
  } color_t;
  function automatic color_t c();
    return SCALE > 4 ? GREEN : RED;
  endfunction
  by_module l ();
endmodule

module by_module;
  int func;
  int arg;
  int named;
  int task_out;
  int color;
  initial begin
    func = mid.f();
    arg = mid.g(4);
    named = mid.g(.a(5));
    mid.t(task_out);
    color = int'(mid.c());
  end
endmodule

module wrap #(
    parameter int SCALE = 1
);
  mid #(.SCALE(SCALE)) u ();
  by_instance r ();
endmodule

module by_instance;
  int func;
  initial func = u.f();
endmodule

module parent_a;
  if (1) begin : cfg
    function automatic int f();
      return 1;
    endfunction
  end
  by_block c ();
endmodule

module parent_b;
  if (1) begin : cfg
    function automatic int f();
      return 2;
    endfunction
  end
  by_block c ();
endmodule

module by_block;
  int func;
  initial func = cfg.f();
endmodule

module defaults #(
    parameter int P = 0
);
  function automatic int f(input int x = 3);
    return x;
  endfunction
  // The default of y differs, but the call below supplies y
  function automatic int g(input int x = 3, input int y = P);
    return 10 * x + y;
  endfunction
  int local_call;
  assign local_call = f(P + 3);
  by_default r ();
endmodule

module by_default;
  int defaulted;
  int supplied;
  initial begin
    defaulted = defaults.f();
    supplied = defaults.g(.y(7));
  end
endmodule

module unrelated;
  function automatic int f(input int x = 77);
    return x;
  endfunction
  int direct;
  assign direct = f();
endmodule

module plain;
  task automatic t(output int r, input int a = 42);
    r = a;
  endtask
  plain_reader r ();
endmodule

module plain_reader;
  int got;
  initial plain.t(got);
endmodule

module same_spec #(
    parameter int P = 0
);
  function automatic int f(input int a = P, input int b = 0);
    return 100 * a + b;
  endfunction
  same_spec_reader r ();
endmodule

module same_spec_reader;
  int got;
  int named;
  initial begin
    got = same_spec.f();
    named = same_spec.f(.b(5));
  end
endmodule
