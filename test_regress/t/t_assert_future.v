// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2025 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv, expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module t (
    input clk
);

  global clocking @(posedge clk);
  endclocking

  logic a;
  sub_derived sub_derived (.clk);

  int cyc = 0;

  //PASSES:
  int count_not_stable;  // Counts changes
  assert property (@(posedge clk) $stable(a))
  else count_not_stable = count_not_stable + 1;

  int count_not_stable_gclk;  // Counts changes
  assert property (@(posedge clk) $stable_gclk(a))
  else count_not_stable_gclk = count_not_stable_gclk + 1;

  int count_changing_gclk;
  assert property (@(posedge clk) $changing_gclk(a)) count_changing_gclk = count_changing_gclk + 1;
  else;

  int count_falling_gclk;
  assert property (@(posedge clk) $falling_gclk(a)) count_falling_gclk = count_falling_gclk + 1;
  else;

  int count_future_gclk;  // Counts changes
  assert property (@(posedge clk) $future_gclk(a) != a) count_future_gclk = count_future_gclk + 1;
  else;

  int count_rising_gclk;
  assert property (@(posedge clk) $rising_gclk(a)) count_rising_gclk = count_rising_gclk + 1;
  else;

  int count_not_steady_gclk;  // Counts changes
  assert property (@(posedge clk) $steady_gclk(a))
  else count_not_steady_gclk = count_not_steady_gclk + 1;

  // A value that does not start at zero, so the first tick is checked against a real value
  logic [6:0] x = 7'h55;
  int count_future_eq_fail;
  assert property (@(posedge clk) $future_gclk(x) == x)
  else count_future_eq_fail = count_future_eq_fail + 1;

  int count_future_eq_disabled_fail;
  assert property (@(posedge clk) disable iff (cyc == 5) $future_gclk(x) == x)
  else count_future_eq_disabled_fail = count_future_eq_disabled_fail + 1;

  int count_steady_x_fail;
  assert property (@(posedge clk) $steady_gclk(x))
  else count_steady_x_fail = count_steady_x_fail + 1;

  always @(posedge clk) begin
`ifdef TEST_VERBOSE
    $display("[%0t] cyc=%0d a=%0x gs=%x gsc=%x", $time, cyc, a, count_not_stable,
             count_not_stable_gclk);
`endif
    cyc <= cyc + 1;
    if (cyc == 5) x <= x + 7'h1;
    if (cyc <= 3) begin
      a <= 0;
      count_not_stable = 0;
      count_not_stable_gclk = 0;
    end
    else if (cyc == 4) begin
      a <= 0;  // stable
    end
    else if (cyc == 5) begin
      a <= 1;  // rise
    end
    else if (cyc == 6) begin
      a <= 1;  // stable
    end
    else if (cyc == 7) begin
      a <= 0;  // fall
    end
    else if (cyc == 10) begin
      `checkd(count_not_stable, 2);
      `checkd(count_not_stable_gclk, 2);
      `checkd(count_changing_gclk, 2);
      `checkd(count_falling_gclk, 1);
      `checkd(count_future_gclk, 2);
      `checkd(count_rising_gclk, 1);
      `checkd(count_not_steady_gclk, 2);
      `checkd(count_future_eq_fail, 1);
      `checkd(count_future_eq_disabled_fail, 0);
      `checkd(count_steady_x_fail, 1);
      `checkd(sub_derived.count_changes, 2);
      `checkd(sub_derived.count_disabled_fail, 1);
      `checkd(sub_derived.count_sampled_disabled_fail, 2);
      `checkd(sub_derived.count_both_fail, 1);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end

endmodule

module sub_derived (
    input clk
);
  // The global clock ticks after the variable is updated in the same time step, which does not
  // change its sampled value
  logic dclk = 0;
  int dcyc = 0;
  logic d = 0;
  logic drst = 0;
  logic dflag = 1;
  always @(posedge clk) begin
    dclk <= ~dclk;
    if (!dclk) begin
      dcyc <= dcyc + 1;
      if (dcyc == 1 || dcyc == 2) d <= ~d;
      drst <= dcyc == 2;
      dflag <= dcyc == 0;
    end
  end

  global clocking @(posedge dclk);
  endclocking

  int count_changes = 0;
  assert property (@(posedge dclk) $future_gclk(d) == d)
  else count_changes = count_changes + 1;

  // The disable condition uses current values
  int count_disabled_fail = 0;
  assert property (@(posedge dclk) disable iff (drst) $future_gclk(d) == d)
  else count_disabled_fail = count_disabled_fail + 1;

  // A sampled value function in the disable condition is sampled
  int count_sampled_disabled_fail = 0;
  assert property (@(posedge dclk) disable iff ($sampled(drst)) $future_gclk(d) == d)
  else count_sampled_disabled_fail = count_sampled_disabled_fail + 1;

  // A variable in the disable condition and in the property has the current and sampled values
  int count_both_fail = 0;
  assert property (@(posedge dclk) disable iff (dflag) $future_gclk(d) == d || dflag)
  else count_both_fail = count_both_fail + 1;
endmodule
