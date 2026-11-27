// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Unique constraints on whole arrays whose elements are set after the object is constructed,
// with the uniqueness and the other constraints on and off

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0)
// verilog_format: on

typedef bit [6:0] word_t;

class Q;
  rand word_t q[$];
  constraint u {unique {q};}
  constraint dom {foreach (q[i]) q[i] inside {7'd7, [7'd10 : 7'd12]};}
  constraint trim {foreach (q[i]) (7'd8 <= q[i]) && (q[i] < 7'd12);}
endclass

class D;
  rand word_t q[];
  bit gate;
  constraint u {unique {q};}
  constraint hard_dom {foreach (q[i]) q[i] inside {[7'd30 : 7'd33]};}
  constraint soft_dom {foreach (q[i]) soft q[i] == 7'd31;}
  constraint cond_dom {foreach (q[i]) if (gate && i == 0) q[i] == 7'd33;}
endclass

class F;
  rand bit signed [6:0] q[3:1];
  constraint u {unique {q};}
  constraint dom {foreach (q[i]) q[i] inside {[-7'sd64 : -7'sd63], 7'sd63};}
  constraint trim {foreach (q[i]) q[i] < 7'sd63;}
endclass

class G;
  rand word_t a[$], b[$];
  constraint u {unique {a, b};}
  constraint da {foreach (a[i]) a[i] <= 7'd2;}
  constraint db {foreach (b[i]) b[i] inside {[7'd1 : 7'd3]};}
endclass

module t;
  int rc;
  bit seen[128];

  // Queue of n elements with uniqueness on or off, domain on or off, narrowed or not
  task automatic queue(int n, bit uOn, bit domOn, bit trimOn, int expRc, bit toggle = 0);
    automatic Q o = new;
    automatic word_t saved[$];
    o.u.constraint_mode(uOn);
    o.dom.constraint_mode(domOn);
    o.trim.constraint_mode(trimOn);
    repeat (n) o.q.push_back(7'd111);
    saved = o.q;
    seen = '{default: 0};
    rc = o.randomize();
    `checkd(rc, expRc);
    if (rc == 0) `checkd(o.q == saved, 1);
    else begin
      `checkd(o.q.size(), n);
      foreach (o.q[i]) begin
        if (uOn) `checkd(seen[o.q[i]], 0);
        seen[o.q[i]] = 1;
        if (domOn) `checkd(o.q[i] inside {7'd7, [7'd10 : 7'd12]}, 1);
        if (trimOn) `checkd(o.q[i] inside {[7'd10 : 7'd11]}, 1);
      end
    end
    if (toggle) begin
      // The same object, its domain off: five distinct values
      o.dom.constraint_mode(0);
      rc = o.randomize();
      `checkd(rc, 1);
      seen = '{default: 0};
      foreach (o.q[i]) begin
        `checkd(seen[o.q[i]], 0);
        seen[o.q[i]] = 1;
      end
    end
  endtask

  // Dynamic array of n elements, the first conditionally fixed
  task automatic dynamic(int n, bit gate, int expRc);
    automatic D o = new;
    automatic word_t saved[];
    o.gate = gate;
    o.q = new[n];
    foreach (o.q[i]) o.q[i] = 7'd110;
    saved = o.q;
    seen = '{default: 0};
    rc = o.randomize();
    `checkd(rc, expRc);
    if (rc == 0) `checkd(o.q == saved, 1);
    else begin
      foreach (o.q[i]) begin
        `checkd(seen[o.q[i]], 0);
        `checkd(o.q[i] inside {[7'd30 : 7'd33]}, 1);
        seen[o.q[i]] = 1;
      end
      if (gate) `checkd(o.q[0], 7'd33);
    end
  endtask

  // Signed fixed-size array of a nonzero descending range
  task automatic fixed(bit trimOn, int expRc);
    automatic F o = new;
    automatic bit signed [6:0] saved[3:1];
    o.trim.constraint_mode(trimOn);
    o.q = '{7'sd20, 7'sd21, 7'sd22};
    saved = o.q;
    seen = '{default: 0};
    rc = o.randomize();
    `checkd(rc, expRc);
    if (rc == 0) `checkd(o.q == saved, 1);
    else begin
      foreach (o.q[i]) begin
        `checkd(seen[$unsigned(o.q[i])], 0);
        `checkd(o.q[i] inside {[-7'sd64 : -7'sd63], 7'sd63}, 1);
        seen[$unsigned(o.q[i])] = 1;
      end
    end
  endtask

  // Two queues in one group
  task automatic group(int na, int expRc);
    automatic G o = new;
    automatic word_t savedA[$], savedB[$];
    repeat (na) o.a.push_back(7'd111);
    repeat (2) o.b.push_back(7'd112);
    savedA = o.a;
    savedB = o.b;
    seen = '{default: 0};
    rc = o.randomize();
    `checkd(rc, expRc);
    if (rc == 0) `checkd(o.a == savedA && o.b == savedB, 1);
    else begin
      foreach (o.a[i]) begin
        `checkd(seen[o.a[i]], 0);
        `checkd(o.a[i] <= 7'd2, 1);
        seen[o.a[i]] = 1;
      end
      foreach (o.b[i]) begin
        `checkd(seen[o.b[i]], 0);
        `checkd(o.b[i] inside {[7'd1 : 7'd3]}, 1);
        seen[o.b[i]] = 1;
      end
    end
  endtask

  initial begin
    queue(4, 1, 1, 0, 1);  // As many elements as values
    queue(5, 1, 1, 0, 0);  // One more
    queue(3, 1, 1, 1, 0);  // One more than the narrowed values
    queue(2, 1, 1, 1, 1);  // As many as the narrowed values
    queue(5, 0, 1, 0, 1);  // Uniqueness off
    queue(5, 1, 0, 0, 1);  // Domain off
    queue(5, 1, 1, 0, 0, 1);  // Fails, then the domain off
    dynamic(4, 0, 1);
    dynamic(4, 1, 1);
    dynamic(5, 0, 0);
    fixed(0, 1);
    fixed(1, 0);
    group(2, 1);
    group(3, 0);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
