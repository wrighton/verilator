// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 PlanV GmbH
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define check_range(gotv,minv,maxv) do if ((gotv) < (minv) || (gotv) > (maxv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d-%0d\n", `__FILE__,`__LINE__, (gotv), (minv), (maxv)); `stop; end while(0);
// verilog_format: on

class FuncConstraintTest;
  rand bit [7:0] value;
  rand bit [7:0] mask;

  function bit [7:0] get_min_value(bit [7:0] m);
    return m & 8'hF0;
  endfunction

  function bit [7:0] get_max_value(bit [7:0] m);
    return m | 8'h0F;
  endfunction

  constraint func_con {
    mask inside {[8'h10 : 8'hF0]};
    value >= get_min_value(mask);
    value <= get_max_value(mask);
  }

  function new();
  endfunction
endclass

class AssocConstRefTest;
  rand int m[int];
  rand int x;
  rand int y;

  function int get_val(const ref int v);
    return v;
  endfunction

  constraint assoc_con {
    foreach (m[i]) m[i] inside {[1 : 50]};
    x == get_val(m[1]) + 1;
  }
endclass

// A function first reached from a constraint is still executed elsewhere
class ConstraintFirstTest;
  rand int x;
  int m[int];

  constraint c {x == get_m(1);}

  function int get_val(const ref int v);
    return v;
  endfunction
  function int get_m(int k);
    return get_val(m[k]);
  endfunction
endclass

module t;
  FuncConstraintTest fct;
  AssocConstRefTest act;
  ConstraintFirstTest cft;
  int rand_ok;
  bit [7:0] min_val;
  bit [7:0] max_val;

  initial begin
    fct = new();

    repeat (10) begin
      rand_ok = fct.randomize();
      `checkd(rand_ok, 1)

      `check_range(fct.mask, 8'h10, 8'hF0)

      min_val = fct.get_min_value(fct.mask);
      max_val = fct.get_max_value(fct.mask);
      `check_range(fct.value, min_val, max_val)
    end

    // Element of an associative array passed to a const ref in a constraint
    act = new;
    act.m[1] = 0;
    act.m[2] = 0;
    repeat (10) begin
      rand_ok = act.randomize() with { y == get_val(m[2]); };
      `checkd(rand_ok, 1)
      `checkd(act.x, act.m[1] + 1)
      `checkd(act.y, act.m[2])
    end

    cft = new;
    `checkd(cft.get_m(5), 0);
    `checkd(cft.m.exists(5), 1);

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
