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

// Test that rand variables used as array indices in constraints are treated
// as symbolic in the solver, not evaluated at C++ constraint setup time.

class RandArrayIndexTest;
  rand bit [1:0] idx;
  rand bit [7:0] data [4];
  rand bit [7:0] selected_value;

  constraint solve_order { solve idx before selected_value; }
  constraint value_match { selected_value == data[idx]; }
  constraint data_values {
    foreach (data[i]) {
      data[i] inside {[8'd10:8'd50]};
    }
  }
endclass

// Cast index into a random dynamic array and queue
class RandDynIndexCastTest;
  rand bit [1:0] idx;
  rand bit [7:0] dyn[];
  rand bit [7:0] q[$];
  rand bit [7:0] dyn_value;
  rand bit [7:0] q_value;

  constraint sizes { dyn.size() == 4; q.size() == 4; }
  constraint value_match {
    dyn_value == dyn[int'(idx)];
    q_value == q[32'(idx)];
  }
endclass

// A state index of another width than 32 bits selects the element of its full value, or no
// element if out of range (IEEE 1800-2023 7.4.5)
class StateWideIndexTest;
  bit [6:0] dyn[];
  bit [6:0] q[$];
  longint idx;
  bit signed [2:0] sidx;
  rand bit [6:0] dyn_value;
  rand bit [6:0] q_value;
  rand bit [6:0] sidx_value;

  constraint value_match {
    dyn_value == dyn[idx];
    q_value == q[idx];
    sidx_value == dyn[sidx];
  }
endclass

module t;
  initial begin
    int randomize_result;
    static RandArrayIndexTest obj = new();
    RandDynIndexCastTest cobj;
    repeat (20) begin
      randomize_result = obj.randomize();
      `checkd(randomize_result, 1);
      `checkd(obj.selected_value, obj.data[obj.idx]);
      `check_range(obj.selected_value, 8'd10, 8'd50)
    end
    cobj = new();
    repeat (20) begin
      randomize_result = cobj.randomize();
      `checkd(randomize_result, 1);
      `checkd(cobj.dyn_value, cobj.dyn[cobj.idx]);
      `checkd(cobj.q_value, cobj.q[cobj.idx]);
    end
    begin
      static StateWideIndexTest sobj = new();
      sobj.dyn = '{3, 42, 5, 6, 7, 8, 9, 10, 11};
      sobj.q = '{13, 14, 15};
      for (int k = 0; k < 6; k++) begin
        sobj.idx = {32'(k % 2), 32'(k / 2)};
        sobj.sidx = 3'(k + 3);
        randomize_result = sobj.randomize();
        `checkd(randomize_result, 1);
        `checkd(sobj.dyn_value, k % 2 == 1 ? 0 : sobj.dyn[k / 2]);
        `checkd(sobj.dyn_value, sobj.dyn[sobj.idx]);
        `checkd(sobj.q_value, k % 2 == 1 ? 0 : sobj.q[k / 2]);
        `checkd(sobj.q_value, sobj.q[sobj.idx]);
        `checkd(sobj.sidx_value, k == 0 ? 6 : k == 5 ? 3 : 0);
        `checkd(sobj.sidx_value, sobj.dyn[sobj.sidx]);
      end
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
