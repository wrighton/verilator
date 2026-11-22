// DESCRIPTION: Verilator: Const casts in procedural concurrent assertions
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__, `__LINE__, (gotv), (expv)); `stop; end while (0);
// verilog_format: on

// IEEE 1800-2023 16.14.6.1: a procedural concurrent assertion saves the values of its const
// expressions when queued, at its statement, for its evaluation and its action blocks. A const
// cast of a variable of the action block takes its value there.
// p until (q || const'(s) == 6) fails at tick 3 for the attempts of ticks 0-3 and at tick 8 for
// those of ticks 7-8; the attempt of tick 6 passes at tick 6, those of ticks 4-5 at tick 5
// (IEEE 1800-2023 16.12.12).
module t;
  localparam int T = 12;
  localparam bit P[T] = '{1, 1, 1, 0, 1, 1, 1, 1, 0, 1, 1, 1};
  localparam bit Q[T] = '{0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0};
  localparam int NFAIL[T] = '{0, 0, 0, 4, 0, 0, 0, 0, 2, 0, 0, 0};
  localparam int NSTARTS = 6;
  localparam int STARTS[NSTARTS] = '{0, 1, 2, 3, 7, 8};  // Ticks of the failing attempts

  bit clk = 0;
  int cyc = 0;
  bit p = P[0];
  bit q = Q[0];
  int s = 0;
  int got[$];
  int got_late[$];
  int got_nest[$];
  int got_local[$];
  int got_sib[$];
  int got_k[$];
  int arr[2] = '{1, 2};
  // A static assertion: its const cast has the value at its evaluation
  int got_static[$];
  assert property (@(posedge clk) p until q)
  else got_static.push_back(const'(s));
  int nfail_pa = 0;
  int nfail_pb = 0;

  // The same in named properties, declared before and after their use
  property pa;
    p until (q || const'(s) == 6);
  endproperty

  always @(posedge clk) begin
    s = cyc;
    assert property (p until (q || const'(s) == 6))
    else begin
      automatic int k = s + 7;
      got.push_back(const'(s));
      got_nest.push_back(const'(const'(s) + 1));
      got_local.push_back(const'(k));
      // Also in an immediate assertion of the action, and after it
      assert (const'(s) == got[got.size()-1]);
      got_sib.push_back(const'(s));
      // A cast of a constant, and of the argument of a with clause, have their values
      got_k.push_back(const'(5) + arr.sum() with (const'(item)));
      // An immediate cover in the action
      cover (const'(s) >= 0);
      #2;
      got_late.push_back(const'(s));
    end
    assert property (pa)
    else ++nfail_pa;
    assert property (pb)
    else ++nfail_pb;
    s = -1;
  end
  property pb;
    p until (q || const'(s) == 6);
  endproperty

  always #5 clk = ~clk;
  always @(posedge clk) cyc <= cyc + 1;

  int nfail = 0;
  int exp_got[$];
  always @(negedge clk) begin
    for (int i = 0; i < NFAIL[cyc-1]; i++) exp_got.push_back(STARTS[nfail+i]);
    nfail += NFAIL[cyc-1];
    `checkd(nfail_pa, nfail);
    `checkd(nfail_pb, nfail);
    got.sort();
    got_late.sort();
    got_nest.sort();
    got_sib.sort();
    `checkd(got.size(), exp_got.size());
    `checkd(got_late.size(), exp_got.size());
    foreach (exp_got[i]) begin
      `checkd(got[i], exp_got[i]);
      `checkd(got_late[i], exp_got[i]);
      `checkd(got_nest.size(), exp_got.size());
      `checkd(got_local.size(), exp_got.size());
      `checkd(got_sib.size(), exp_got.size());
      `checkd(got_nest[i], exp_got[i] + 1);
      // At the action, after the statement following the assertion
      `checkd(got_local[i], 6);
      `checkd(got_sib[i], exp_got[i]);
      `checkd(got_k[i], 8);
    end
    if (cyc < T) begin
      p = P[cyc];
      q = Q[cyc];
    end
    else begin
      `checkd(nfail, NSTARTS);
      // p until q fails at tick 3 for the attempts of ticks 0-3 and at tick 8 for those of
      // ticks 6-8, after the always block left s at -1
      `checkd(got_static.size(), 7);
      foreach (got_static[i]) `checkd(got_static[i], -1);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
