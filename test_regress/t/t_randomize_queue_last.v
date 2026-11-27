// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// A constraint on q[$] or q[$ - k] of a random queue holds of its last elements, at the size
// the solve gives it, or at the size it has if not solved

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define check_range(gotv,minv,maxv) do if ((gotv) < (minv) || (gotv) > (maxv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d-%0d\n", `__FILE__,`__LINE__, (gotv), (minv), (maxv)); `stop; end while(0);
// verilog_format: on

class Solved;
  rand byte unsigned q[$];
  constraint c {
    q.size() inside {[2 : 5]};
    q[$] == 5;
    q[0] == 3;
  }
endclass

class Offset;
  rand byte unsigned q[$];
  constraint c {
    q[$-1] == 7;
    q.size() == 4;
  }
endclass

// The size is not constrained, so it stays
class Kept;
  rand byte unsigned q[$];
  constraint c {q[$] == 5;}
endclass

// Only a size of two or more satisfies it
class Order;
  rand byte unsigned q[$];
  constraint c {
    q.size() inside {[1 : 4]};
    q[$] > q[0];
  }
endclass

// The size is kept, and the offset solved: the element is at the solved offset
class KeptOffset;
  rand byte unsigned q[$];
  rand int k;
  int off;
  constraint c {
    k == off;
    q[$-k] == 77;
  }
endclass

// No element at the end: an element the queue does not have makes no solution
class Missing;
  rand byte unsigned q[$];
  constraint c {q[$-3] == 5;}
endclass

// A random offset past either end: the elements it reaches do not exist
class OffsetRange;
  rand byte unsigned q[$];
  rand int k;
  bit far;
  constraint c {
    q[$-k] == 5;
    if (far) k inside {-2, -1, 2, 3};
    else k inside {-1, 0};
  }
endclass

// Offsets of other widths: narrower ones extended by their sign, wider ones saturated, so
// that a value past the int range reaches no element rather than one wrapped back
`define WIDTHS \
  rand byte unsigned q[$]; \
  rand bit [1:0] k2; \
  rand byte k8; \
  rand longint kp; \
  rand longint kn; \
  rand bit [39:0] ku; \
  constraint c_widths { \
    k2 == 1; \
    q[$-k2] == 11; \
    k8 inside {-1, 2}; \
    q[$-k8] == 22; \
    kp inside {64'sh1_0000_0001, 3}; \
    q[$-kp] == 33; \
    kn inside {-64'sh1_0000_0000, 4}; \
    q[$-kn] == 44; \
    ku inside {40'h1_0000_0005, 5}; \
    q[$-ku] == 55; \
  }
class KeptWidths;
  `WIDTHS
endclass
// Solved from each size the queue starts with, within the range or past it
class Started;
  rand int q[$];
  constraint c {
    q.size() inside {[1 : 5]};
    q[$] == 7;
  }
endclass

class SolvedWidths;
  `WIDTHS
  constraint c_size {q.size() == 6;}
endclass

module t;
  initial begin
    automatic Solved s = new;
    automatic Offset o = new;
    automatic Kept k = new;
    automatic KeptOffset ko = new;
    automatic Missing m = new;
    automatic OffsetRange r2 = new;
    automatic KeptWidths kw = new;
    automatic SolvedWidths sw = new;
    automatic Order r = new;
    automatic Started st = new;
    automatic int ok;
    automatic bit sizes[int];
    repeat (20) begin
      ok = s.randomize();
      `checkd(ok, 1);
      `check_range(s.q.size(), 2, 5);
      `checkd(s.q[s.q.size() - 1], 5);
      `checkd(s.q[0], 3);
      sizes[s.q.size()] = 1;
      ok = s.randomize() with {q[$-1] == 9;};
      `checkd(ok, 1);
      `check_range(s.q.size(), 3, 5);
      `checkd(s.q[s.q.size() - 2], 9);
      `checkd(s.q[s.q.size() - 1], 5);
      ok = o.randomize();
      `checkd(ok, 1);
      `checkd(o.q.size(), 4);
      `checkd(o.q[2], 7);
      ok = r.randomize();
      `checkd(ok, 1);
      `check_range(r.q.size(), 2, 4);
      if (r.q[r.q.size() - 1] <= r.q[0]) `stop;
    end
    `check_range(sizes.num(), 2, 4);
    for (int n = 2; n <= 6; ++n) begin
      for (int off = 0; off < n; ++off) begin
        ko.q.delete();
        for (int j = 0; j < n; ++j) ko.q.push_back(8'(29 + 7 * j));
        ko.off = off;
        ko.k = (off + 1) % n;
        ok = ko.randomize();
        `checkd(ok, 1);
        `checkd(ko.q.size(), n);
        `checkd(ko.k, off);
        `checkd(ko.q[n - 1 - off], 77);
      end
    end
    // Empty, then shorter than the offset
    ok = m.randomize();
    `checkd(ok, 0);
    m.q = '{1, 2};
    ok = m.randomize();
    `checkd(ok, 0);
    m.q = '{1, 2, 3, 4};
    ok = m.randomize();
    `checkd(ok, 1);
    `checkd(m.q.size(), 4);
    `checkd(m.q[0], 5);
    // Past the end (k < 0) or before the first element (k > size - 1)
    r2.q = '{1, 2};
    r2.far = 1;
    ok = r2.randomize();
    `checkd(ok, 0);
    r2.far = 0;
    repeat (10) begin
      ok = r2.randomize();
      `checkd(ok, 1);
      `checkd(r2.k, 0);
      `checkd(r2.q.size(), 2);
      `checkd(r2.q[1], 5);
    end
    kw.q = '{1, 2, 3, 4, 5, 6};
    repeat (10) begin
      ok = kw.randomize();
      `checkd(ok, 1);
      `checkd(kw.q.size(), 6);
      `checkd(kw.k8, 2);
      `checkd(kw.kp, 3);
      `checkd(kw.kn, 4);
      `checkd(kw.q[4], 11);
      `checkd(kw.q[3], 22);
      `checkd(kw.q[2], 33);
      `checkd(kw.q[1], 44);
      `checkd(kw.ku, 5);
      `checkd(kw.q[0], 55);
      ok = sw.randomize();
      `checkd(ok, 1);
      `checkd(sw.q.size(), 6);
      `checkd(sw.k8, 2);
      `checkd(sw.kp, 3);
      `checkd(sw.kn, 4);
      `checkd(sw.q[4], 11);
      `checkd(sw.q[3], 22);
      `checkd(sw.q[2], 33);
      `checkd(sw.q[1], 44);
      `checkd(sw.ku, 5);
      `checkd(sw.q[0], 55);
    end
    for (int start = 0; start <= 7; ++start) begin
      repeat (4) begin
        st.q.delete();
        for (int i = 0; i < start; ++i) st.q.push_back(100 + i);
        ok = st.randomize();
        `checkd(ok, 1);
        `check_range(st.q.size(), 1, 5);
        `checkd(st.q[st.q.size() - 1], 7);
      end
    end
    k.q = '{1, 2, 3};
    ok = k.randomize();
    `checkd(ok, 1);
    `checkd(k.q.size(), 3);
    `checkd(k.q[2], 5);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
