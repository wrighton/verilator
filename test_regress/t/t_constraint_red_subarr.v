// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Antmicro
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

class Sub;
  rand int darr[];
  function new();
    darr = new[3];
  endfunction
endclass

class ReductionDynSubArr;
  rand int arr[5][];
  rand int a;

  typedef struct {rand int arr[];} Subcls;

  rand Subcls sc;
  rand Sub sub;

  function new();
    sc.arr = new[5];
    sub = new;
    foreach (arr[i]) begin
      arr[i] = new[5];
    end
  endfunction

  constraint red_a {
    a + arr[0].sum() == 10;
    a + arr[1].product() == 10;
    a + arr[2].xor() == 10;
    a + arr[3].or() == 10;
    a + arr[4].and() == 10;
  }

  constraint red_b {
    a + sc.arr.sum() == 10;
    a + sc.arr.product() == 10;
    a + sc.arr.xor() == 10;
    a + sc.arr.or() == 10;
    a + sc.arr.and() == 10;
  }

  constraint red_c {a + sub.darr.sum() == 10;}

  function void check();
    `checkd(a + arr[0].sum(), 10);
    `checkd(a + arr[1].product(), 10);
    `checkd(a + arr[2].xor(), 10);
    `checkd(a + arr[3].or(), 10);
    `checkd(a + arr[4].and(), 10);
    `checkd(a + sc.arr.sum(), 10);
    `checkd(a + sc.arr.product(), 10);
    `checkd(a + sc.arr.xor(), 10);
    `checkd(a + sc.arr.or(), 10);
    `checkd(a + sc.arr.and(), 10);
    `checkd(a + sub.darr.sum(), 10);
  endfunction
endclass

module t;
  initial begin
    automatic ReductionDynSubArr sub = new();
    automatic int ok;
    repeat (5) begin
      ok = sub.randomize();
      `checkd(ok, 1);
      sub.check();
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
