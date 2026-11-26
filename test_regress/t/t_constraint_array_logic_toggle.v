// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__, `__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// A rand_mode(0) associative array is held with a constant-array default for missing keys,
// a fixed-size one without
class ToggleArray;
  rand bit [3:0] a[int];
  rand bit [3:0] fixed_arr[2];
  rand int unsigned idx;
  rand bit [3:0] v, fixed_v;
  constraint c {
    idx == 1;
    v == a[idx];
    fixed_v == fixed_arr[idx];
  }
  function new();
    a[0] = 0;
    a[1] = 0;
  endfunction
endclass

module t;
  initial begin
    automatic ToggleArray obj = new;
    int ok;
    ok = obj.randomize();
    `checkd(ok, 1);
    `checkd(obj.idx, 1);
    `checkd(obj.v, obj.a[1]);

    obj.a[0] = 4'h3;
    obj.a[1] = 4'h5;
    obj.a.rand_mode(0);
    obj.fixed_arr = '{4'h6, 4'h7};
    obj.fixed_arr.rand_mode(0);
    ok = obj.randomize();
    `checkd(ok, 1);
    `checkd(obj.idx, 1);
    `checkd(obj.v, 5);
    `checkd(obj.a[0], 3);
    `checkd(obj.a[1], 5);
    `checkd(obj.fixed_v, 7);
    obj.a.rand_mode(1);
    ok = obj.randomize();
    `checkd(ok, 1);
    `checkd(obj.fixed_v, 7);

    obj.fixed_arr.rand_mode(1);
    ok = obj.randomize();
    `checkd(ok, 1);
    `checkd(obj.idx, 1);
    `checkd(obj.v, obj.a[1]);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
