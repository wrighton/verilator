// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module t;
  bit clk = 0;
  bit a = 0;  // Default sampled value 0
  bit [6:0] v = 7'h55;  // Default sampled value 'h55
  logic [14:0] w = 15'h1234;  // Default sampled value 'h1234
  int npass = 0, nfail = 0, nrose = 0, nrfail = 0;
  int tick = 0;

  initial begin
    a = 1;
    v = 7'h2a;
    w = 15'h0f0f;
    #0 clk = 1;  // Posedge at time 0, after every process waits on it
    #5 clk = 0;
    #5 clk = 1;  // Posedge at 10
    #5 clk = 0;
    #5;
    // Tick 0: sampled a is 0, so a1 fails and $rose(a) is false
    // Tick 10: sampled a is 1, so a1 passes and $rose(a) is true
    `checkh(npass, 1);
    `checkh(nfail, 1);
    `checkh(nrose, 1);
    `checkh(nrfail, 1);
    `checkh(tick, 2);
    $write("*-* All Finished *-*\n");
    $finish;
  end

  // Time 0 has the default sampled values, also before any clock tick
  initial begin
    `checkh($sampled(a), 1'b0);
    `checkh($sampled(v), 7'h55);
    `checkh($sampled(w), 15'h1234);
  end

  a1: assert property (@(posedge clk) a) npass++; else nfail++;
  a2: assert property (@(posedge clk) $rose(a)) nrose++; else nrfail++;

  always @(posedge clk) begin
    if (tick == 0) begin
      `checkh($sampled(a), 1'b0);
      `checkh($rose(a), 1'b0);
      `checkh($fell(a), 1'b0);
      `checkh($sampled(v), 7'h55);
      `checkh($stable(v), 1'b1);
      `checkh($changed(v), 1'b0);
      `checkh($past(v), 7'h55);
      `checkh($sampled(w), 15'h1234);
      `checkh($past(w), 15'h1234);
    end
    else begin
      `checkh($sampled(a), 1'b1);
      `checkh($rose(a), 1'b1);
      `checkh($sampled(v), 7'h2a);
      `checkh($stable(v), 1'b0);
      `checkh($changed(v), 1'b1);
      `checkh($past(v), 7'h55);
      `checkh($sampled(w), 15'h0f0f);
      `checkh($past(w), 15'h1234);
    end
    tick++;
  end

  // Also when a lone constant write in an initial procedure sets the variable
  bit g;
  initial g = 1;
  bit [6:0] gv;
  initial gv = 7'h2a;
  int gtick = 0;
  always @(posedge clk) begin
    `checkh($sampled(g), gtick != 0);
    `checkh($past(g), 1'b0);
    `checkh($rose(g), gtick != 0);
    `checkh($sampled(gv), gtick == 0 ? 7'h00 : 7'h2a);
    `checkh($past(gv), 7'h00);
    `checkh($stable(gv), gtick == 0);
    gtick++;
  end

  // A value change function compares sampled values, not a value written earlier in the
  // time step
  bit [6:0] c = 0;
  int n = 0;
  always @(posedge clk) begin
    c = c + 7'h41;
    `checkh($sampled(c), c - 7'h41);
    `checkh($rose(c), n == 1);
    `checkh($fell(c), 1'b0);
    `checkh($stable(c), n == 0);
    `checkh($changed(c), n == 1);
    n++;
  end

  // Nor a value another process wrote with a blocking assignment earlier in the time step,
  // whichever process runs first
  bit [6:0] d = 7'h11;
  bit e = 0;
  always @(posedge clk) begin
    d = d + 7'h23;
    e = ~e;
  end
  int m = 0;
  always @(posedge clk) begin
    `checkh($sampled(d), m == 0 ? 7'h11 : 7'h34);
    `checkh($past(d), 7'h11);
    `checkh($stable(d), m == 0);
    `checkh($changed(d), m == 1);
    `checkh($sampled(e), m == 1);
    `checkh($rose(e), m == 1);
    `checkh($fell(e), 1'b0);
    `checkh($stable(e), m == 0);
    m++;
  end
endmodule
