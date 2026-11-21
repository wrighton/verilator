// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Increment or decrement of a module variable in the initializer of a
// function or task local, or of another module variable, is a driver of
// that variable (no UNDRIVEN)
module t (
  input clk
);
  // Each variable is driven only by its function's local initializer
  int post_inc;
  function automatic int f_post_inc();
    int v = post_inc++;
    return v;
  endfunction

  int pre_inc;
  function automatic int f_pre_inc();
    int v = ++pre_inc;
    return v;
  endfunction

  int post_dec;
  function automatic int f_post_dec();
    int v = post_dec--;
    return v;
  endfunction

  int pre_dec;
  function automatic int f_pre_dec();
    int v = --pre_dec;
    return v;
  endfunction

  // Module variable initializer, run once
  int mod_inc;
  int mod_v = mod_inc++;

  // Task local
  int task_inc;
  task automatic t_task_inc(output int o);
    int v = task_inc++;
    o = v;
  endtask

  int cyc = 0;
  always @(posedge clk) begin
    int got;
    cyc <= cyc + 1;
    got = f_post_inc();
    `checkd(got, cyc);
    got = f_pre_inc();
    `checkd(got, cyc + 1);
    got = f_post_dec();
    `checkd(got, -cyc);
    got = f_pre_dec();
    `checkd(got, -cyc - 1);
    `checkd(mod_v, 0);
    `checkd(mod_inc, 1);
    t_task_inc(got);
    `checkd(got, cyc);
    if (cyc == 9) begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end

  // Increment within a larger initializer expression, of a variable also
  // driven elsewhere: only the increment temporary was reported
  int unsigned n;
  function automatic int unsigned next3();
    int unsigned pick = n++ % 3;
    return pick;
  endfunction
  initial begin
    int unsigned got;
    n = 0;
    got = next3();
    `checkd(got, 0);
    got = next3();
    `checkd(got, 1);
    got = next3();
    `checkd(got, 2);
    got = next3();
    `checkd(got, 0);
    `checkd(n, 4);
  end
endmodule
