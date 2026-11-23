// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__, `__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

class ToggleArray;
  rand bit [3:0] a[2];
  rand int unsigned idx;
  rand bit [3:0] v;
  constraint c {
    idx == 1;
    v == a[idx];
  }
endclass

module t;
  initial begin
    automatic ToggleArray obj = new;
    int ok;
    ok = obj.randomize();
    `checkd(ok, 1);
    `checkd(obj.idx, 1);
    `checkd(obj.v, obj.a[1]);

    obj.a = '{4'h3, 4'h5};
    obj.a.rand_mode(0);
    ok = obj.randomize();
    `checkd(ok, 1);
    `checkd(obj.idx, 1);
    `checkd(obj.v, 5);
    `checkd(obj.a[0], 3);
    `checkd(obj.a[1], 5);

    obj.a.rand_mode(1);
    ok = obj.randomize();
    `checkd(ok, 1);
    `checkd(obj.idx, 1);
    `checkd(obj.v, obj.a[1]);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
