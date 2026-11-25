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
  logic clk = 0;
  always #5 clk = ~clk;

  // A value with side effects, read once in the cycle of its match item
  int unsigned calls;
  function automatic bit check_period(realtime cur, realtime period);
    ++calls;
    return ($realtime - cur) == period;
  endfunction

  int unsigned passes, fails;
  // verilator lint_off SIDEEFFECT
  property p_clk(realtime clk_period);
    realtime current;
    bit pass;
    @(posedge clk) (1, current = $realtime)
        |=> (1, pass = check_period(current, clk_period)) ##0 pass;
  endproperty
  // verilator lint_on SIDEEFFECT
  assert property (p_clk(10)) passes++;
  else fails++;

  int unsigned bad_passes, bad_fails;
  assert property (p_clk(20)) bad_passes++;
  else bad_fails++;

  // A value with side effects, calling a static class method
  class Counter;
    static int unsigned count;
    static function int add(int a, int b);
      ++count;
      return a + b;
    endfunction
  endclass
  int cnt = 0;
  always @(posedge clk) cnt <= cnt + 1;
  int unsigned static_passes, static_fails;
  // verilator lint_off SIDEEFFECT
  property p_static;
    int v;
    @(posedge clk) (1, v = Counter::add(cnt, 1)) ##0 (v == cnt + 1);
  endproperty
  // verilator lint_on SIDEEFFECT
  assert property (p_static) static_passes++;
  else static_fails++;

  // Read in the cycle of the match item of an overlapped implication
  int unsigned bumps;
  function automatic int bump(int x);
    ++bumps;
    return x;
  endfunction
  int unsigned overlap_passes, overlap_fails;
  // verilator lint_off SIDEEFFECT
  property p_overlap;
    int v;
    @(posedge clk) (1, v = bump(cnt)) |-> (v == cnt);
  endproperty
  // verilator lint_on SIDEEFFECT
  assert property (p_overlap) overlap_passes++;
  else overlap_fails++;

  // A value of an imported function not declared pure, e.g. a C reference model, in a guarded
  // single-cycle property
  import "DPI-C" function int ref_model(int x);
  int unsigned model_passes, model_fails;
  property p_model;
    int v;
    @(posedge clk) (cnt[0], v = ref_model(cnt)) |-> (v == 2 * cnt);
  endproperty
  assert property (p_model) model_passes++;
  else model_fails++;

  // The same through a function with temporaries (not automatic, so kept between calls)
  function int wrapped_model(int x);
    int r;
    int prev;
    if (x < 0) return 0;
    begin
      r = ref_model(x);
    end
    prev = r;
    return prev;
  endfunction
  int unsigned wrapped_passes, wrapped_fails;
  property p_wrapped_model;
    int v;
    @(posedge clk) (cnt[0], v = wrapped_model(cnt)) |-> (v == 2 * cnt);
  endproperty
  assert property (p_wrapped_model) wrapped_passes++;
  else wrapped_fails++;

  // A value of a function writing a variable it does not read, in a guarded single-cycle property
  int recorded;
  function automatic int record(int x);
    recorded = x;
    return x + 1;
  endfunction
  int unsigned record_passes, record_fails;
  // verilator lint_off SIDEEFFECT
  property p_record;
    int v;
    @(posedge clk) (cnt[0], v = record(cnt)) |-> (v == cnt + 1);
  endproperty
  // verilator lint_on SIDEEFFECT
  assert property (p_record) record_passes++;
  else record_fails++;

  // A function with a temporary assigned a call of another function, guarded and not
  function automatic int twice(int x);
    return 2 * x;
  endfunction
  function int calc(int a);
    int tmp;
    tmp = twice(a);
    return tmp;
  endfunction
  int unsigned calc_passes, calc_fails, calc_open_passes, calc_open_fails;
  property p_calc;
    int v;
    @(posedge clk) (cnt[0], v = calc(cnt)) |-> (v == 2 * cnt);
  endproperty
  assert property (p_calc) calc_passes++;
  else calc_fails++;
  property p_calc_open;
    int v;
    @(posedge clk) (1, v = calc(cnt)) |-> (v == 2 * cnt);
  endproperty
  assert property (p_calc_open) calc_open_passes++;
  else calc_open_fails++;

  // A value of one match item writing a variable another only reads
  int stable;
  function automatic int set_stable(int x);
    stable = 0;
    return x + 1;
  endfunction
  function automatic int add_stable(int x);
    return x + stable;
  endfunction
  int unsigned split_passes, split_fails;
  // verilator lint_off SIDEEFFECT
  property p_split;
    int v, w;
    @(posedge clk) (cnt[0], v = set_stable(cnt), w = add_stable(cnt)) |-> (v == w + 1);
  endproperty
  // verilator lint_on SIDEEFFECT
  assert property (p_split) split_passes++;
  else split_fails++;

  // A procedural assertion under a condition, of the reference model
  property p_model_unclocked;
    int v;
    (1, v = ref_model(5)) |-> (v == 10);
  endproperty
  int unsigned proc_passes, proc_fails;
  always @(posedge clk) begin
    if (cnt[1]) begin
      assert property (p_model_unclocked) proc_passes++;
      else proc_fails++;
    end
  end

  initial begin
    #100;
    `checkd(calc_passes, 10);
    `checkd(calc_fails, 0);
    `checkd(calc_open_passes, 10);
    `checkd(calc_open_fails, 0);
    `checkd(split_passes, 10);
    `checkd(split_fails, 0);
    `checkd(proc_passes, 4);
    `checkd(proc_fails, 0);
    `checkd(record_passes, 10);
    `checkd(record_fails, 0);
    `checkd(model_passes, 10);
    `checkd(wrapped_passes, 10);
    `checkd(wrapped_fails, 0);
    `checkd(model_fails, 0);
    `checkd(overlap_passes, 10);
    `checkd(overlap_fails, 0);
    if (bumps == 0) `stop;
    `checkd(static_passes, 10);
    `checkd(static_fails, 0);
    if (Counter::count == 0) `stop;
    `checkd(passes, 9);
    `checkd(fails, 0);
    `checkd(bad_passes, 0);
    `checkd(bad_fails, 9);
    if (calls == 0) `stop;
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
