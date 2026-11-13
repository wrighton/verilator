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

// A rand index wider than the array's select width that is out of range reads the
// default value rather than a valid element (IEEE 1800-2023 7.4.6)
class OutOfRangeIndexTest;
  rand int idx;
  rand bit [39:0] widx;
  rand int unsigned arr[3];
  rand int unsigned arr53[5:3];
  rand bit [1:0] bidx;
  bit [1:0] nidx = 1;
  rand int ni;
  rand int nj;
  rand int unsigned narr[2][3];
  constraint values_c {
    foreach (narr[a, b]) narr[a][b] == a * 10 + b;
    arr[0] == 0;
    arr[1] == 7;
    arr[2] == 0;
    arr53[3] == 0;
    arr53[4] == 9;
    arr53[5] == 0;
  }
  // verilator lint_off WIDTHTRUNC
  constraint select_c {
    arr[idx] == 7;
    arr[widx] == 7;
    arr53[idx + 3] == 9;
    arr[bidx] == 7;
    arr[nidx] == 7;
    narr[ni][nj] == 12;
    narr[ni][1] == 11;
  }
  // verilator lint_on WIDTHTRUNC
endclass

class OutOfRangeUnsatTest;
  rand int idx;
  rand int unsigned arr[3];
  constraint c {
    idx == 5;
    arr[1] == 7;
    arr[idx] == 7;
  }
endclass

// A random index selecting a member of an unpacked struct or class array element
// must verilate. Solving such a select is not supported, so its constraint is
// disabled before randomizing.
typedef struct {bit [6:0] tag;} tag_t;

class RandIndexItem;
  rand bit [14:0] val;
endclass

class RandIndexMemberTest;
  rand int idx;
  rand tag_t tags[3];
  rand RandIndexItem items[3];
  constraint member_c {
    tags[idx].tag == 7'h5;
    items[idx].val == 15'h6;
  }
  function new();
    foreach (items[i]) items[i] = new;
  endfunction
endclass

module t;
  initial begin
    int randomize_result;
    static RandArrayIndexTest obj = new();
    static OutOfRangeIndexTest oor = new;
    static OutOfRangeUnsatTest unsat = new;
    static RandIndexMemberTest member = new;
    repeat (20) begin
      randomize_result = oor.randomize();
      `checkd(randomize_result, 1);
      `checkd(oor.idx, 1);
      `checkd(oor.widx, 1);
      `checkd(oor.bidx, 1);
      `checkd(oor.ni, 1);
      `checkd(oor.nj, 2);
    end
    randomize_result = unsat.randomize();
    `checkd(randomize_result, 0);
    member.member_c.constraint_mode(0);
    randomize_result = member.randomize();
    `checkd(randomize_result, 1);
    repeat (20) begin
      randomize_result = obj.randomize();
      `checkd(randomize_result, 1);
      `checkd(obj.selected_value, obj.data[obj.idx]);
      `check_range(obj.selected_value, 8'd10, 8'd50)
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
