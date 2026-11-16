// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define check_range(gotv,minv,maxv) do if ((gotv) < (minv) || (gotv) > (maxv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d-%0d\n", `__FILE__,`__LINE__, (gotv), (minv), (maxv)); `stop; end while(0);
// verilog_format: on

// A phased solve...before (IEEE 1800-2023 18.5.9) of scalar layers keeps one
// solver base across its phases; the driver counts the bases built

// Every layer accepts nearly any value, so each phase keeps the base the first built
class Keep;
  rand bit [6:0] a;
  rand bit [6:0] b;
  rand bit [6:0] c;
  constraint c_order {
    solve a before b;
    solve b before c;
  }
  constraint c_hard {
    b != a;
    c != b;
  }
  constraint c_soft_a {soft a != 7'd5;}
  constraint c_soft_c {soft c != 7'd9;}
endclass

// A random trial value almost never fits len, so after one round of trials its phase is
// solved afresh without trials, even as the constraint's bound changes between calls, until
// it is tried again
class Narrow;
  rand bit [3:0] k;
  rand int len;
  int lim;
  constraint c_order {solve k before len;}
  constraint c_bound {len inside {[1 : lim]};}
  constraint c_hard {len != 32'(k);}
endclass

module t;
  initial begin
    int calls;
    if ($test$plusargs("decay")) begin
      // Trials that always fit, then trials that almost never do
      Narrow n;
      int rc;
      n = new;
      n.lim = 16;
      n.c_bound.constraint_mode(0);
      repeat (300) begin
        rc = n.randomize();
        `checkd(rc, 1);
      end
      n.c_bound.constraint_mode(1);
      repeat (100) begin
        rc = n.randomize();
        `checkd(rc, 1);
        `check_range(n.len, 1, 16);
      end
    end else if ($value$plusargs("narrow=%d", calls)) begin
      Narrow n;
      int rc;
      n = new;
      for (int i = 0; i < calls; ++i) begin
        n.lim = 10 + i % 7;
        rc = n.randomize();
        `checkd(rc, 1);
        `check_range(n.len, 1, n.lim);
        `checkd(n.len != 32'(n.k), 1);
      end
    end else begin
      Keep k;
      int rc;
      k = new;
      repeat (50) begin
        rc = k.randomize();
        `checkd(rc, 1);
        `checkd(k.b != k.a && k.c != k.b && k.a != 5 && k.c != 9, 1);
      end
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
