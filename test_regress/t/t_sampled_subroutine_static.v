// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

// The arguments and variables of a static task or function are static, shared by all its calls
// (IEEE 1800-2023 6.21, 13.3.2), so a sampled value function samples their values at clock ticks
// (IEEE 1800-2023 16.9.3). Those of an automatic one have their current values (IEEE 1800-2023
// 16.5.1).
module t;
  bit clk = 0;
  bit [6:0] cnt = 0;  // Equal to the clock tick number until the tick's update
  default clocking cb @(posedge clk);
  endclocking

  task static past_arg(input bit [6:0] data, output bit [6:0] o);
    o = $past(data);
  endtask
  task static past_arg2(input bit [6:0] data, output bit [6:0] o);
    o = $past(data);
  endtask
  function static bit [6:0] past_fn(input bit [6:0] data);
    return $past(data);
  endfunction
  task automatic past_auto(input bit [6:0] data, output bit [6:0] o);
    o = $past(data);
  endtask
  task automatic past_static_var(input bit [6:0] data, output bit [6:0] o);
    static bit [6:0] v;
    v = data;
    o = $past(v);
  endtask
  // Argument in the clocking event
  task static rose_on(input bit c, output bit o);
    o = $rose(cnt[0], c);
  endtask
  // Never called
  task static stable_arg(input bit [6:0] data, output bit o);
    o = $stable(data);
  endtask

  initial begin
    repeat (8) begin
      #5 clk = 1;
      #5 clk = 0;
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end

  bit [6:0] o1, o2a, o2b, o3, o4, o5, o6a, o6b;
  always @(posedge clk) begin
    // Test: the argument's previous sampled value, from the previous call
    past_arg(cnt, o1);
    `checkd(o1, cnt >= 2 ? cnt - 7'd2 : 7'd0);
    // Test: calls share the argument, so it has the value of the last call
    past_arg2(cnt, o2a);
    past_arg2(cnt + 7'd50, o2b);
    `checkd(o2a, cnt >= 2 ? cnt + 7'd48 : 7'd0);
    `checkd(o2b, o2a);
    `checkd(past_fn(cnt), cnt >= 2 ? cnt - 7'd2 : 7'd0);
    // Test: the past value of an automatic argument is its current value
    past_auto(cnt, o3);
    `checkd(o3, cnt);
    past_static_var(cnt, o4);
    `checkd(o4, cnt >= 2 ? cnt - 7'd2 : 7'd0);
    // Test: concurrent calls
    fork
      past_arg(cnt, o6a);
      past_arg(cnt, o6b);
    join
    `checkd(o6a, o6b);
    cnt <= cnt + 7'd1;
  end
  bit rose;
  always @(clk) begin
    rose_on(clk, rose);
    // Sampled at both clock edges, the update is seen at the falling edge
    `checkd(rose, !clk && cnt[0]);
  end
endmodule
