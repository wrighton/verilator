// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

class Cls;
  rand int a;
  rand int b;
  rand int c;
  int t;

  function int f_out(output int o);
    o = 1;
    return 2;
  endfunction
  function int f_inout(inout int o);
    return o;
  endfunction
  function int f_ref(ref int o);
    return o;
  endfunction
  function int f_cref(const ref int o);  // OK
    return o;
  endfunction

  constraint c_out {a == f_out(t);}  // Illegal 18.5.11
  constraint c_inout {b == f_inout(t);}  // Illegal 18.5.11
  constraint c_ref {c == f_ref(t);}  // Illegal 18.5.11
  constraint c_cref {c == f_cref(t);}
endclass

module t;
  Cls obj;
  int x;

  initial begin
    obj = new;
    void'(obj.randomize() with {a == obj.f_ref(obj.t);});  // Illegal 18.5.11
    void'(std::randomize(x) with {x == obj.f_out(obj.t);});  // Illegal 18.5.11
  end
endmodule
