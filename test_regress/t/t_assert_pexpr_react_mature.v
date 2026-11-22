// DESCRIPTION: Verilator: Procedural concurrent assertion instances mature in the Observed region
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__, `__LINE__, (gotv), (expv)); `stop; end while (0);
// verilog_format: on

// IEEE 1800-2023 16.14.6: executing a procedural concurrent assertion queues a pending instance,
// with its constant and automatic inputs (16.14.6.1); the instance matures in the Observed region
// and only then begins its attempt. 16.14.6.2: a flush point of the process (its resumption from
// an event control or wait statement, or a disable of its outermost scope) clears its pending
// instances; a delay, or a disable of an inner scope (16.14.6.4), does not. A matured attempt is
// not affected by the procedure's later execution, such as a disable fork.
// Six clocks, at 5, 15, ..., 55; p is always true, q always true, q2 true from the clock of cyc 3.
module t;
  bit clk = 0;
  int cyc = 0;
  bit p = 1;
  bit q = 1;
  bit q2 = 0;
  bit a = 0;

  // A resumption from an event control before the Observed region flushes the instance
  event e1;
  always @(posedge clk) #0 ->e1;
  int nflush = 0, nflushb = 0;
  always @(posedge clk) begin
    assert property (p until q) ++nflush;
    assert property (q) ++nflushb;
    @(e1);
  end
  // A delay is not a flush point
  int ndelay = 0, ndelayb = 0;
  always @(posedge clk) begin
    assert property (p until q) ++ndelay;
    assert property (q) ++ndelayb;
    #1;
  end
  // A disable of the outermost scope flushes; one of an inner scope does not
  int nouter = 0, ninner = 0;
  always @(posedge clk) begin : outer_d
    assert property (p until q) ++nouter;
    disable outer_d;
  end
  // Also when disabled from another process, while suspended in a delay
  int next = 0;
  always @(posedge clk) begin : ext_d
    assert property (p until q) ++next;
    #1;
  end
  always @(posedge clk) #0 disable ext_d;
  always @(posedge clk) begin
    begin : inner_d
      assert property (p until q) ++ninner;
      disable inner_d;
    end
  end
  // Each execution in a loop queues an instance with its own automatic input
  int got_loop[$];
  always @(posedge clk) begin
    for (int i = 0; i < 3; i++) assert property (p until q) got_loop.push_back(i);
  end
  // Automatic inputs have their values at the statement
  int ncap = 0, nbcap = 0, nbcapf = 0;
  always @(posedge clk) begin
    automatic int k = 1;
    assert property (p until (q && k == 1)) ++ncap;
    assert property (k == 1) ++nbcap;
    else ++nbcapf;
    k = 0;
  end
  // Sampled value functions have the values of the clock (16.9.3): a toggles every cycle, so
  // a is only stable at the first clock, from its initial value
  int nstb = 0, npstb = 0, nstbf = 0;
  always @(posedge clk) begin
    assert property ($stable(a)) ++nstb;
    else ++nstbf;
    assert property (1 until $stable(a)) ++npstb;
  end
  // An attempt waiting for an event, from a procedure clocked by it
  event ev;
  always @(posedge clk) begin
    ->ev;
  end
  int nev = 0;
  always @(ev) assert property (p until q2) ++nev;
  // The waits of an attempt spanning clocks, and of its action, are not flush points of the
  // procedure
  int nmc = 0;
  always @(posedge clk) begin
    assert property (p until q2) begin
      #1;
      ++nmc;
    end
  end
  // A disable fork of the procedure does not reach the attempts, which are not its children
  int ndf = 0;
  always @(posedge clk) begin
    assert property (p until q2) ++ndf;
    disable fork;
  end

  always #5 clk = ~clk;
  always @(posedge clk) cyc <= cyc + 1;

  always @(negedge clk) begin
    a = ~a;
    q2 = cyc >= 3;
    if (cyc == 6) begin
      `checkd(nflush, 0);
      `checkd(nflushb, 0);
      `checkd(ndelay, 6);
      `checkd(ndelayb, 6);
      `checkd(nouter, 0);
      `checkd(next, 0);
      `checkd(ninner, 6);
      `checkd(got_loop.size(), 18);
      foreach (got_loop[i]) `checkd(got_loop[i], i % 3);
      `checkd(ncap, 6);
      `checkd(nbcap, 6);
      `checkd(nbcapf, 0);
      `checkd(nstb, 1);
      `checkd(nstbf, 5);
      `checkd(npstb, 1);
      `checkd(nev, 6);
      `checkd(nmc, 6);
      `checkd(ndf, 6);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
