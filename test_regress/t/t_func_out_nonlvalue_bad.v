// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

class Cls;
  int m_v;
  function automatic int f_inout(inout int io);
    io++;
    return io;
  endfunction
endclass

module t;
  typedef int arr2_t[2];

  task automatic t_out(output int o);
    o = 1;
  endtask
  task automatic t_ref(ref int r);
    r = 4;
  endtask
  task automatic t_arr(output arr2_t o);
    o = '{2, 3};
  endtask
  function automatic int f_inout(inout int io);
    io++;
    return io;
  endfunction
  function automatic int f_val();
    return 1;
  endfunction

  int a, b, r;
  int arr[4];
  int q[$];
  int aa[string];
  logic [31:0] vec;
  logic [15:0] lo, hi;
  struct packed {logic [15:0] x, y;} s;
  Cls c;

  initial begin
    // Legal: valid on the left-hand side of a procedural assignment
    t_out(a);
    t_out(arr[1]);
    t_out(q[0]);
    t_out(aa["k"]);
    t_out(vec[a+:32]);
    t_out({lo, hi});
    t_out({>>{lo, hi}});
    t_out(s);
    c = new;
    t_out(c.m_v);
    t_arr('{a, b});
    t_ref(a);
    r = f_inout(arr[a]);
    r = c.f_inout(arr[a]);
    r = c.f_inout(q[1]);
    r = c.f_inout(vec[31:0]);
    foreach (arr[i]) r = c.f_inout(arr[i]);
    // Illegal (IEEE 1800-2023 13.5)
    t_out(a + b);
    r = f_inout(a | b);
    t_out(f_val());
    t_out((a == 1) ? b : r);
    t_out(int'(a));
    t_out({lo, hi + 16'd1});
    t_out({lo - 16'd1, hi});
    t_out({2{lo}});
    r = c.f_inout(a - b);
  end
endmodule
