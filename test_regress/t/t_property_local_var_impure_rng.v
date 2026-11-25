// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

`timescale 1ns / 1ns

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module t;
  // A local variable assigned a value drawing a random value in a called function draws it only
  // when a match reads it, so not between the clock ticks of the property, but at each attempt
  bit clk;
  int unsigned fails;
  int unsigned draws[$];
  function automatic int unsigned draw();
    return $urandom();
  endfunction
  function automatic bit record(int unsigned x);
    draws.push_back(x);
    return 1'b1;
  endfunction
  // verilator lint_off SIDEEFFECT
  property p;
    int unsigned x;
    @(posedge clk) (1, x = draw()) ##0 record(x);
  endproperty
  // verilator lint_on SIDEEFFECT
  assert property (p)
  else fails++;

  // Also through a class method an override of which draws it, with the time
  class source;
    virtual function time value();
      return 0;
    endfunction
  endclass
  class random_source extends source;
    virtual function time value();
      return time'($urandom());
    endfunction
  endclass
  source src;
  function automatic time through_handle();
    return src.value();
  endfunction
  int unsigned method_fails;
  // verilator lint_off SIDEEFFECT
  property p_method;
    time y;
    @(posedge clk) (1, y = $time + through_handle()) ##0 (y >= $time);
  endproperty
  // verilator lint_on SIDEEFFECT
  assert property (p_method)
  else method_fails++;

  // The procedural random values drawn after reseeding are the same while the clock is idle
  task automatic check_reseed(int seed_value);
    int seed;
    int unsigned expected;
    seed = seed_value;
    void'($urandom(seed));
    expected = $urandom();
    seed = seed_value;
    void'($urandom(seed));
    #1;
    `checkh($urandom(), expected);
  endtask

  initial begin
    random_source rs;
    rs = new;
    src = rs;
    #1;
    check_reseed(4243);
    `checkd(draws.size(), 0);
    // Attempts, each drawing a value at its match
    repeat (6) begin
      #1 clk = 1;
      #1 clk = 0;
    end
    `checkd(fails, 0);
    `checkd(method_fails, 0);
    // Drawn at least once for each attempt, not once for all
    if (draws.size() < 6) `stop;
    `checkd(draws.unique().size(), draws.size());
    check_reseed(1234);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
