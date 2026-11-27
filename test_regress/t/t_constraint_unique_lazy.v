// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Whole arrays whose elements are all to differ
class Wide;
  rand int qf[$];
  constraint c {unique {qf};}
  function new(int n);
    repeat (n) qf.push_back(0);
  endfunction
endclass

class Tight;
  rand int qt[$];
  constraint c {
    unique {qt};
    foreach (qt[i]) qt[i] inside {[0 : 59]};
  }
  function new;
    repeat (40) qt.push_back(0);
  endfunction
endclass

// Values spread over a domain only a little larger than the elements need
class Narrow;
  rand bit [10:0] qr[$];
  constraint c {unique {qr};}
  function new;
    repeat (100) qr.push_back(0);
  endfunction
endclass

class WideElement;
  rand bit [69:0] qw[$];
  constraint c {unique {qw};}
  function new;
    repeat (40) qw.push_back(0);
  endfunction
endclass

// Solved in layers, and of a solved size
class Ordered;
  rand int sel;
  rand int qo[$];
  constraint c {
    sel inside {[0 : 3]};
    solve sel before qo;
    qo.size() == 40 + sel;
    unique {qo};
    foreach (qo[i]) qo[i] inside {[0 : 999]};
  }
endclass

class Never;
  rand int qn[$];
  constraint c {
    unique {qn};
    qn[0] == qn[1];
  }
  function new;
    for (int i = 0; i < 40; ++i) qn.push_back(i);
  endfunction
endclass

module t;
  int randomize_result;

  function automatic int dups(int q[$]);
    int seen[int];
    int n = 0;
    foreach (q[i]) begin
      if (seen.exists(q[i])) ++n;
      seen[q[i]] = 1;
    end
    return n;
  endfunction

  initial begin
    begin
      automatic int n = 200;
      automatic Wide w;
      void'($value$plusargs("n=%d", n));
      w = new(n);
      repeat (3) begin
        randomize_result = w.randomize();
        `checkd(randomize_result, 1);
        `checkd(w.qf.size(), n);
        `checkd(dups(w.qf), 0);
      end
    end
    begin
      // A domain too small to spread the elements without equal ones
      automatic Tight t = new;
      repeat (3) begin
        randomize_result = t.randomize();
        `checkd(randomize_result, 1);
        `checkd(dups(t.qt), 0);
        foreach (t.qt[i]) `checkd(t.qt[i] inside {[0 : 59]}, 1);
      end
    end
    begin
      automatic Narrow nr = new;
      repeat (6) begin
        automatic bit seen[bit [10:0]];
        randomize_result = nr.randomize();
        `checkd(randomize_result, 1);
        foreach (nr.qr[i]) seen[nr.qr[i]] = 1;
        `checkd(seen.size(), 100);
      end
    end
    begin
      automatic WideElement we = new;
      automatic bit seen[bit [69:0]];
      randomize_result = we.randomize();
      `checkd(randomize_result, 1);
      foreach (we.qw[i]) seen[we.qw[i]] = 1;
      `checkd(seen.size(), 40);
    end
    begin
      automatic Ordered o = new;
      repeat (3) begin
        randomize_result = o.randomize();
        `checkd(randomize_result, 1);
        `checkd(o.qo.size(), 40 + o.sel);
        `checkd(dups(o.qo), 0);
        foreach (o.qo[i]) `checkd(o.qo[i] inside {[0 : 999]}, 1);
      end
    end
    begin
      // Unsatisfiable only with the elements differing: the values are left as they were
      automatic Never v = new;
      randomize_result = v.randomize();
      `checkd(randomize_result, 0);
      foreach (v.qn[i]) `checkd(v.qn[i], i);
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
