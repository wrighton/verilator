// DESCRIPTION: Verilator: Concurrent assertion actions run in the Reactive region
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__, `__LINE__, (gotv), (expv)); `stop; end while (0);
// verilog_format: on

// IEEE 1800-2023 4.4.2.6, 4.4.2.8, 4.5: action blocks run in the Reactive region, after the
// design's NBAs of the time step, and their NBAs update in the Re-NBA region, before the
// active region set resumes.
// p until q fails at tick 3 for the attempts of ticks 0-3 (the attempt of tick 3 fails in its
// first activation, the others resume), at tick 8 for those of ticks 6-8, and passes at tick 5
// for those of ticks 4-5 (IEEE 1800-2023 16.12.12).
module t;
  localparam int T = 16;
  localparam bit P[T] = '{1, 1, 1, 0, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1};
  localparam bit Q[T] = '{0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0};
  localparam int NFAIL[T] = '{0, 0, 0, 4, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0, 0};
  localparam int NPASS[T] = '{0, 0, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0};

  bit clk = 0;
  int cyc = 0;  // Updated by a design NBA at each tick
  bit p = P[0];
  bit q = Q[0];
  int nfail = 0;  // Completions, blocking
  int nfail_coal = 0;  // Coalescing Re-NBA counter
  int npass = 0;
  int npass_coal = 0;
  int act_cyc[$];  // What the actions of a tick read of 'cyc'
  int r = 0;  // Updated by a Re-NBA in the action
  int r2 = 0;  // Updated by a Re-NBA in a task the action calls
  int seen_r = 0;
  int seen_r2 = 0;
  int seen_m = 0;
  int lag = 0;
  int exp_nfail = 0;
  int exp_coal = 0;
  int exp_npass = 0;
  int exp_r = 0;
  int exp_m = 0;
  int prev_r = 0;

  task automatic set_r2(int v);
    r2 <= v;
  endtask
  // Updated by a method both the design and the action call
  class Box;
    int v;
    int w;  // Updated by a Re-NBA through a handle in the action
    task put(int a);
      v <= a;
    endtask
  endclass
  Box box = new;
  // Updated by a Re-NBA in a virtual method the action calls
  class Base;
    int v;
    virtual task set(int a);
      v <= a;
    endtask
  endclass
  class Derived extends Base;
    virtual task set(int a);
      v <= a + 1;
    endtask
  endclass
  Base h;
  int seen_v = 0;
  int seen_w = 0;
  initial begin
    automatic Derived d = new;
    h = d;
  end

  assert property (@(posedge clk) p until q)
  begin
    ++npass;
    npass_coal <= npass_coal + 1;
  end
  else begin
    act_cyc.push_back(cyc);
    nfail_coal <= nfail_coal + 1;
    r <= cyc;
    set_r2(cyc);
    box.put(200 + cyc);
    box.w <= cyc + 7;
    h.set(cyc);
    ++nfail;
  end

  always #5 clk = ~clk;

  always @(posedge clk) begin
    cyc <= cyc + 1;
    box.put(100 + cyc);
    lag <= r;
  end

  // Active logic woken by the actions, after the reactive region set
  always @(nfail) begin
    seen_r = r;
    seen_r2 = r2;
    seen_m = box.v;
    seen_v = h.v;
    seen_w = box.w;
  end

  // The oracle deliberately uses if/stop, never an assertion
  always @(negedge clk) begin
    // Tick 'cyc - 1' was sampled at the last posedge
    exp_nfail += NFAIL[cyc-1];
    exp_npass += NPASS[cyc-1];
    exp_m = 100 + cyc - 1;
    if (NFAIL[cyc-1] != 0) begin
      ++exp_coal;
      exp_r = cyc;
      exp_m = 200 + cyc;
    end
    `checkd(nfail, exp_nfail);
    `checkd(npass, exp_npass);
    `checkd(nfail_coal, exp_coal);
    `checkd(npass_coal, exp_npass == 0 ? 0 : 1);
    `checkd(act_cyc.size(), NFAIL[cyc-1]);
    foreach (act_cyc[i]) `checkd(act_cyc[i], cyc);
    act_cyc.delete();
    `checkd(r, exp_r);
    `checkd(r2, exp_r);
    `checkd(box.v, exp_m);
    `checkd(h.v, exp_r == 0 ? 0 : exp_r + 1);
    `checkd(box.w, exp_r == 0 ? 0 : exp_r + 7);
    `checkd(lag, prev_r);
    prev_r = r;
    if (NFAIL[cyc-1] != 0) begin
      `checkd(seen_r, cyc);
      `checkd(seen_r2, cyc);
      `checkd(seen_m, 200 + cyc);
      `checkd(seen_v, cyc + 1);
      `checkd(seen_w, cyc + 7);
    end
    if (cyc < T) begin
      p = P[cyc];
      q = Q[cyc];
    end
    else begin
      `checkd(exp_nfail, 7);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
