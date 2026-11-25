// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

`timescale 1ns / 1ns

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module t;
  bit clk, data;
  int tick;
  always #5 clk = ~clk;
  always @(negedge clk) begin
    ++tick;
    data = !data;
  end
  clocking cb @(posedge clk);
    input data, tick;
  endclocking

  // A value with the time and a sampled value function, clocked by a clocking block
  int unsigned passes, fails;
  property p;
    bit x;
    @(cb) (cb.tick >= 2, x = ($realtime > 1000.0) ^ $past(cb.data))
        |=> (x == $past(cb.data, 2));
  endproperty
  assert property (p) passes++;
  else fails++;

  // A value reading the time through a function, also with another local variable
  function automatic realtime stamp();
    return $realtime;
  endfunction
  int unsigned func_passes, func_fails;
  property p_func;
    bit x;
    @(cb) (cb.tick >= 2, x = (stamp() > 1000.0) ^ $past(cb.data)) |=> (x == $past(cb.data, 2));
  endproperty
  assert property (p_func) func_passes++;
  else func_fails++;

  longint cnt = 0;
  always @(posedge clk) cnt <= cnt + 1;
  int unsigned local_passes, local_fails;
  property p_local;
    longint a, b;
    @(cb) (1, a = cnt) ##1 (1, b = a * 1000 + longint'(stamp()))
        ##1 (b == (cnt - 2) * 1000 + longint'($realtime) - 10);
  endproperty
  assert property (p_local) local_passes++;
  else local_fails++;

  initial begin
    $assertvacuousoff;
    #100;
    `checkd(passes, 7);
    `checkd(fails, 0);
    `checkd(func_passes, 7);
    `checkd(func_fails, 0);
    `checkd(local_passes, 8);
    `checkd(local_fails, 0);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
