// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Functions called in constraints (IEEE 1800-2023 18.5.11) whose return value reads variables
// that inlining it into the constraint cannot substitute

package pkg;
  // Static function: its return value has no initializer
  function bit [7:0] f_part(bit [7:0] d);
    f_part = d;
    f_part[1] = 1'b1;
  endfunction
endpackage

class Policy;
  static Policy m_inst;
  static int s_scale = 3;
  int m_offset = 3;
  static function Policy get();
    return m_inst;
  endfunction
  function int offset(int d);
    return d + m_offset;
  endfunction
  function int scaled(int d);
    return d * s_scale;
  endfunction
endclass

class Cls;
  rand int b_init;
  rand int b_assign;
  rand int b_int;
  rand int b_unused;
  rand int b_ret;
  rand int b_port;
  rand bit [7:0] b_part;
  rand bit [7:0] b_pkg_part;
  rand bit [7:0] b_low;
  rand int b_scaled;
  rand int b_uninit;
  rand int b_other;
  rand int b_lparam;
  rand int arg;  // Used with rand_mode(0), so the functions see its current value
  rand bit [3:0] src;
  rand bit [3:0] tgt;
  rand bit is_amo;
  // verilator lint_off CONSTRAINTIGN
  extern function int f_init(int d);
  function int f_assign(int d);
    Policy policy;
    policy = Policy::get();
    return (policy != null) ? policy.offset(d) : -1;
  endfunction
  function int f_int(int d);
    int t = d * 2;
    return t + 1;
  endfunction
  function int f_ret(int d);
    f_ret = f_ret + d;
  endfunction
  function int f_port(int d);
    d = d + 1;
    return d * 2;
  endfunction
  function bit [7:0] f_part(bit [7:0] d);
    f_part = d;
    f_part[0] = 1'b1;
  endfunction
  function bit [7:0] f_low(bit [7:0] d);
    f_low[3:0] = d[3:0];
  endfunction
  function int f_uninit(int d);
    int t;
    return d + t;
  endfunction
  function int f_lparam(int d);
    localparam int K = 3;
    return d + K;
  endfunction
  function int f_unused(int d);
    int t = 5;
    return d + 1;
  endfunction
  constraint c_init {b_init == f_init(arg);}
  constraint c_assign {b_assign == f_assign(arg);}
  constraint c_int {b_int == f_int(arg);}
  constraint c_ret {b_ret == f_ret(arg);}
  constraint c_port {b_port == f_port(arg);}
  constraint c_part {b_part == f_part(arg[7:0]);}
  constraint c_pkg_part {b_pkg_part == pkg::f_part(arg[7:0]);}
  constraint c_low {b_low == f_low(arg[7:0]);}
  constraint c_other {b_other == Policy::get().offset(arg);}
  constraint c_uninit {b_uninit == f_uninit(arg);}
  constraint c_scaled {b_scaled == Policy::get().scaled(b_init);}
  constraint c_unused {b_unused == f_unused(b_init);}
  constraint c_lparam {b_lparam == f_lparam(b_init);}
  constraint c_amo {if (f_init(32'(src)) == 32'(tgt)) is_amo == 0;}
  // verilator lint_on CONSTRAINTIGN
endclass

function int Cls::f_init(int d);
  Policy policy = Policy::get();
  return (policy != null) ? policy.offset(d) : -1;
endfunction

module t;
  initial begin
    automatic Cls obj = new;
    int randomize_result;
    Policy::m_inst = new;
    obj.arg.rand_mode(0);
    for (int i = 0; i < 10; ++i) begin
      obj.arg = i * 7;
      Policy::m_inst.m_offset = i;
      randomize_result = obj.randomize();
      `checkd(randomize_result, 1)
      `checkd(obj.b_init, i * 8)
      `checkd(obj.b_assign, i * 8)
      `checkd(obj.b_int, i * 14 + 1)
      `checkd(obj.b_ret, i * 7)
      `checkd(obj.b_port, i * 14 + 2)
      `checkd(obj.b_part, 8'((i * 7) | 1))
      `checkd(obj.b_pkg_part, 8'((i * 7) | 2))
      `checkd(obj.b_low, 8'((i * 7) & 15))
      `checkd(obj.b_other, i * 8)
      `checkd(obj.b_uninit, i * 7)
      `checkd(obj.b_scaled, obj.b_init * 3)
      `checkd(obj.b_unused, obj.b_init + 1)
      `checkd(obj.b_lparam, obj.b_init + 3)
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
