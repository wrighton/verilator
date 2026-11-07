// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Antmicro
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

typedef int int_arr_t[];

class A;
  rand int x;
endclass

class Cls;
  int_arr_t arr[];
  task body();
    int ok;
    A a;
    a = new;
    arr = new[2];
    arr[1] = new[2];
    arr[1][1] = 123;
    repeat (40) begin
      ok = a.randomize() with {x == arr[1][1];};
      `checkd(ok, 1);
      `checkd(a.x, arr[1][1]);
    end
  endtask
endclass

class B;
  rand int x;
  rand int arr[][];
endclass

class Cls2;
  task body();
    int ok;
    B b;
    b = new;
    b.arr = new[2];
    b.arr[1] = new[2];
    b.x = 1;
    b.arr[1][1] = 2;
    repeat (40) begin
      ok = b.randomize() with {x == arr[1][1];};
      `checkd(ok, 1);
      `checkd(b.x, b.arr[1][1]);
    end
  endtask
endclass

class Cls3;
  rand int_arr_t arr;
  task body();
    int ok;
    B b;
    b = new;
    b.arr = new[2];
    b.arr[1] = new[2];
    b.x = 1;
    b.arr[1][1] = 2;
    arr = new[2];
    arr[1] = 3;
    repeat (40) begin
      ok = b.randomize() with {x == arr[1][1];};
      `checkd(ok, 1);
      `checkd(b.x, b.arr[1][1]);
      `checkd(arr[1], 3);
    end
  endtask
endclass

class Cls4;
  rand int x;
  rand int_arr_t arr[];
  task body();
    int ok;
    arr = new[2];
    arr[1] = new[2];
    arr[1][1] = 123;
    repeat (40) begin
      ok = randomize() with {x == arr[1][1];};
      `checkd(ok, 1);
      `checkd(x, arr[1][1]);
    end
  endtask
endclass

class Cls5;
  rand int_arr_t arr[];
  task body();
    int ok;
    arr = new[2];
    arr[0] = new[2];
    arr[1] = new[2];
    arr[1][1] = 123;
    repeat (40) begin
      // Only the argument arr[0] is random; arr[1][1] is a state value
      ok = std::randomize(arr[0]) with {arr[0][0] == arr[1][1];};
      `checkd(ok, 1);
      `checkd(arr[0][0], 123);
      `checkd(arr[1][1], 123);
    end
  endtask
endclass

module t;
  Cls c;
  Cls2 c2;
  Cls3 c3;
  Cls4 c4;
  Cls5 c5;
  initial begin
    c = new;
    c2 = new;
    c3 = new;
    c4 = new;
    c5 = new;
    c.body();
    c2.body();
    c3.body();
    c4.body();
    c5.body();
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
