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

class SimpleRandClass;
  rand bit [7:0] value;
  constraint value_con {value > 0 && value < 200;}
  function new();
  endfunction
endclass

int cnt;

function automatic int idx();
  ++cnt;
  return 1;
endfunction

class Holder;
  SimpleRandClass items[3];
  function new();
    foreach (items[i]) items[i] = new;
  endfunction
  function int run();
    return items[idx()].randomize() with {value > 100;};
  endfunction
  task run_fork();
    fork
      void'(items[idx()].randomize());
    join_none
  endtask
endclass

module t;
  SimpleRandClass obj;
  int rand_result;
  SimpleRandClass h[3];
  SimpleRandClass n[3];
  Holder holder;

  function automatic SimpleRandClass get_obj();
    ++cnt;
    return h[2];
  endfunction

  initial begin
    obj = null;
    rand_result = obj.randomize();
    `checkd(rand_result, 0);

    obj = new();
    rand_result = obj.randomize();
    `checkd(rand_result, 1);
    `check_range(obj.value, 1, 199);

    // Target with side effects is evaluated once
    foreach (h[i]) h[i] = new;
    rand_result = h[idx()].randomize();
    `checkd(rand_result, 1);
    `checkd(cnt, 1);
    rand_result = h[idx()].randomize() with {value > 100;};
    `checkd(rand_result, 1);
    `checkd(cnt, 2);
    `check_range(h[1].value, 101, 199);
    `checkd(h[0].value, 0);
    `checkd(h[2].value, 0);
    rand_result = get_obj().randomize();
    `checkd(rand_result, 1);
    `checkd(cnt, 3);
    rand_result = n[idx()].randomize();
    `checkd(rand_result, 0);
    `checkd(cnt, 4);
    rand_result = n[idx()].randomize() with {value > 100;};
    `checkd(rand_result, 0);
    `checkd(cnt, 5);
    holder = new;
    `checkd(holder.run(), 1);
    `checkd(cnt, 6);
    `check_range(holder.items[1].value, 101, 199);
    holder.run_fork();
    #1;
    `checkd(cnt, 7);

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
