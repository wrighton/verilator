// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// IEEE 1800-2023 23.2.2.4: Input port default values shall be constant expressions

package pkg;
  int x = 1;
  localparam int LP = 4;
  function automatic int nonconst();
    return x;
  endfunction
  function automatic int triple(int v);
    return v * 3;
  endfunction
endpackage

int unit_var = 2;

class C;
  // Legal: a function writing its input, first called from a static initializer
  static bit s_ok = define_access("rw");
  static function bit define_access(string name);
    name = name.toupper();
    return name == "RW";
  endfunction
endclass

module sub #(
    parameter int P = 2
) (
    input int a,
    input int ok_param = P + pkg::LP,
    input int ok_func = pkg::triple(P),
    input int ok_bits = $bits(a),
    input int bad_pkg_var = pkg::x,  // <--- Bad
    input int bad_unit_var = unit_var,  // <--- Bad
    input int bad_port = a,  // <--- Bad
    input int bad_func = pkg::nonconst(),  // <--- Bad
    output int o
);
  assign o = a + ok_param + ok_func + ok_bits + bad_pkg_var + bad_unit_var + bad_port + bad_func;
endmodule

module t;
  function automatic int inc(int a);
    a = a + 1;
    return a;
  endfunction
  int s = inc(1);
  bit c_ok = C::s_ok;
  int o;
  sub u (
      .a(1),
      .o(o)
  );
endmodule
