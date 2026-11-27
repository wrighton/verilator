// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// A 'unique' constraint makes all its members pairwise distinct: the singular
// variables, and the leaf elements of the arrays it names (IEEE 1800-2023 18.5.4).

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0)
// verilog_format: on

typedef bit [2:0] val_t;
typedef enum bit [1:0] {
  E_ZERO = 0,
  E_THREE = 3
} sparse_t;

// Checks that no two of 'vals' are equal
class Check #(
    type T = val_t
);
  static function void distinct(T vals[$], int line);
    foreach (vals[i])
    foreach (vals[j])
    if (i < j && vals[i] == vals[j]) begin
      $write("%%Error: %s:%0d: members %0d and %0d both hold %0d\n", `__FILE__, line, i, j,
             vals[i]);
      `stop;
    end
  endfunction
endclass

class ScalarsArray;
  rand val_t x, y;
  rand val_t arr[4];
  constraint u {unique {x, arr, y};}
endclass

// Arrays with non-zero bounds in both directions
class Bounds;
  rand val_t x;
  rand val_t up[3:5];
  rand val_t down[6:4];
  constraint u {unique {up, x, down};}
endclass

class Containers;
  rand val_t x;
  rand val_t d[];
  rand val_t q[$];
  constraint sz {
    d.size() == 3;
    q.size() == 2;
  }
  constraint u {unique {d, x, q};}
endclass

// A size-constrained queue whose elements must all differ from a scalar of one bit
class Resize;
  rand bit q[$];
  rand bit x;
  int n;
  constraint c {q.size() == n; unique {q, x};}
endclass

class ResizeCond;
  rand bit sel;
  rand bit q[$];
  rand bit x;
  int n;
  constraint c {
    q.size() == n;
    if (sel) {
      unique {q, x};
    }
  }
endclass

class ResizeInline;
  rand bit q[$];
  rand bit x;
endclass

class Grow;
  rand bit [1:0] q[$];
  rand bit [1:0] x;
  int n;
  constraint c {q.size() == n; unique {x, q};}
endclass

// Queues of random size, whose members have a value each only for some sizes
class SizeRange;
  rand bit q[$];
  rand bit x;
  constraint c {q.size() inside {[1:2]}; unique {q, x};}
endclass

class SizeRangeWide;
  rand bit [1:0] q[$];
  rand bit [1:0] a, b;
  int lo, hi;
  constraint c {q.size() inside {[lo:hi]}; unique {q, a, b};}
endclass

class SizeRangeMultiDim;
  rand bit [1:0] q[$][2];
  rand bit [1:0] a;
  constraint c {q.size() inside {[1:2]}; unique {q, a};}
endclass

// An enum has only its named values
// Multidimensional queues of random size: a new element brings the leaves of its type,
// none if that is dynamically sized
class SizeMultiDimGrow;
  rand bit [1:0] q[$][2];
  rand bit [1:0] a;
  int lo;
  constraint c {q.size() inside {[lo:3]}; unique {q, a};}
endclass

class SizeMultiDimDyn;
  rand bit [1:0] q[$][$];
  rand bit [1:0] a;
  constraint c {q.size() inside {[1:3]}; unique {q, a};}
endclass

// Whole arrays whose elements are set after the object is constructed
class WholeSized;
  rand val_t q1[$];
  rand val_t q2[$];
  int n1;
  constraint s {q1.size() == n1;}
  constraint u {unique {q1, q2};}
endclass

class WholeFree;
  rand val_t q1[$];
  rand val_t d[];
  rand val_t aa[int];
  constraint u {unique {q1, d, aa};}
endclass

class SizeRangeEnum;
  rand sparse_t q[$];
  rand sparse_t x;
  constraint c {q.size() inside {[1:2]}; unique {q, x};}
endclass

// A queue of a member object whose size is solved
class SizeSub;
  rand bit [1:0] q[$];
endclass

class SizeMember;
  rand SizeSub s;
  rand bit [1:0] x;
  constraint c {s.q.size() inside {[1:3]}; unique {s.q, x};}
  function new;
    s = new;
  endfunction
endclass

// Only some sizes of the queue of a member object leave a value for each member
class SizeMemberTight;
  rand SizeSub s;
  rand bit [1:0] x, y;
  int lo;
  constraint c {s.q.size() inside {[lo:4]}; unique {s.q, x, y};}
  function new;
    s = new;
  endfunction
endclass

// A multidimensional queue of a member object
class SizeSubMultiDim;
  rand bit [1:0] q[$][2];
endclass

class SizeMemberMultiDim;
  rand SizeSubMultiDim s;
  rand bit [1:0] x;
  constraint c {s.q.size() inside {[1:2]}; unique {s.q, x};}
  function new;
    s = new;
  endfunction
endclass

// Members named as solver reserved words
class Reserved;
  rand val_t select[3];
  rand val_t bvadd;
  rand val_t concat[$];
  rand val_t ite[2];
  rand val_t distinct[2];
  constraint c_mixed {unique {bvadd, select};}
  constraint c_size {concat.size() inside {[1:4]}; unique {concat, bvadd};}
  constraint c_whole {unique {ite, distinct};}
endclass

class SizeRangeInt;
  rand int q[$];
  rand int y;
  constraint c {q.size() inside {[1:3]}; unique {q, y};}
endclass

// Containers that hold fewer than two elements
class Small;
  rand val_t x, y;
  rand val_t none[];
  rand val_t one[$];
  constraint sz {
    none.size() == 0;
    one.size() == 1;
  }
  constraint u_none {unique {none};}
  constraint u_x_none {unique {x, none};}
  constraint u_x_one {unique {x, one};}
  constraint u_y_none_one {unique {none, y, one};}
  constraint narrow {
    x inside {[0 : 1]};
    y inside {[0 : 1]};
    one[0] inside {[0 : 1]};
  }
endclass

class MultiDim;
  rand val_t x;
  rand val_t m[1:2][5:3];
  constraint u {unique {m, x};}
endclass

// Inner dimensions sized at run time
class MultiDimDyn;
  rand val_t x;
  rand val_t md[2][];
  rand val_t mq[2][$];
  rand val_t ma[2][int];
  constraint u {unique {md, x, mq, ma};}
  function new;
    md[0] = new[1];
    md[1] = new[2];
    mq[1] = '{0};
    ma[0][-3] = 0;
    ma[1][5] = 0;
  endfunction
endclass

class Sub;
  rand val_t arr[3];
endclass

// An array of a rand member object
class Member;
  rand Sub s;
  rand val_t x;
  constraint u {unique {s.arr, x};}
  function new;
    s = new;
  endfunction
endclass

class Assoc;
  rand val_t x;
  rand val_t aa[string];
  constraint u {unique {x, aa};}
  function new;
    aa["one"] = 0;
    aa["two"] = 0;
    aa["three"] = 0;
  endfunction
endclass

// A state variable and a rand variable with rand_mode off are members too
class States;
  bit [1:0] st;
  rand bit [1:0] off;
  rand bit [1:0] r[2];
  constraint u {unique {st, r, off};}
endclass

// State arrays are members too, read but never written
class StateArrays;
  bit [6:0] a[2];
  bit [6:0] b[2];
  rand bit [6:0] r[2];
  constraint u_state {unique {a, b};}
  constraint u_rand {unique {a, r};}
endclass

// A whole array with rand_mode off is a member too
class ArrMode;
  rand val_t a[3];
  rand val_t b[3];
  constraint u {unique {a, b};}
endclass

class Cond;
  rand bit sel;
  rand val_t x;
  rand val_t q[$];
  constraint sz {q.size() == 5;}
  constraint u {
    if (sel) {
      unique {q, x};
    }
  }
endclass

// A randc variable may index a member
class RandcIndex;
  randc bit [1:0] i;
  rand val_t arr[4];
  rand val_t b;
  constraint u {unique {arr[i], b};}
endclass

class Inline;
  rand val_t x;
  rand val_t arr[5];
endclass

// Many members, in a dynamically sized group, and an array of more than 100 elements
class Large;
  rand bit [7:0] x, y;
  rand bit [7:0] d[];
  rand bit [7:0] big[101];
  constraint sz {d.size() == 40;}
  constraint u {unique {x, d, y};}
  constraint u_big {unique {big};}
endclass

module t;
  initial begin
    automatic ScalarsArray sa = new;
    automatic Bounds bd = new;
    automatic Containers co = new;
    automatic Resize rz = new;
    automatic ResizeCond rzc = new;
    automatic ResizeInline rzi = new;
    automatic Grow gr = new;
    automatic SizeRange sr = new;
    automatic SizeRangeWide srw = new;
    automatic SizeRangeMultiDim srm = new;
    automatic SizeMultiDimGrow smg = new;
    automatic SizeMultiDimDyn smd = new;
    automatic WholeSized wsz = new;
    automatic WholeFree wfr = new;
    automatic SizeRangeEnum sre = new;
    automatic SizeMember smb = new;
    automatic SizeMemberTight smt = new;
    automatic SizeMemberMultiDim smm = new;
    automatic Reserved rsv = new;
    automatic SizeRangeInt sri = new;
    automatic Small sm = new;
    automatic MultiDim md = new;
    automatic MultiDimDyn mdd = new;
    automatic Member mb = new;
    automatic Assoc as_ = new;
    automatic States st = new;
    automatic StateArrays sta = new;
    automatic ArrMode am = new;
    automatic Cond cd = new;
    automatic RandcIndex ri = new;
    automatic Inline il = new;
    automatic Large lg = new;
    automatic val_t sx;
    automatic val_t sarr[3];
    val_t vals[$];
    bit [1:0] nibs[$];
    bit [7:0] lvals[$];
    int ok;

    for (int n = 0; n < 10; ++n) begin
      ok = sa.randomize();
      `checkd(ok, 1);
      Check#()::distinct({sa.x, sa.y, sa.arr}, `__LINE__);

      ok = bd.randomize();
      `checkd(ok, 1);
      Check#()::distinct({bd.x, bd.up, bd.down}, `__LINE__);

      ok = co.randomize();
      `checkd(ok, 1);
      `checkd(co.d.size(), 3);
      `checkd(co.q.size(), 2);
      Check#()::distinct({co.x, co.d, co.q}, `__LINE__);

      // Shrinking from three elements to one, then growing from one to three
      rz.n = 1;
      rz.q = '{0, 0, 0};
      ok = rz.randomize();
      `checkd(ok, 1);
      `checkd(rz.q.size(), 1);
      Check#(bit)::distinct({rz.x, rz.q}, `__LINE__);

      rzc.n = 1;
      rzc.q = '{0, 0, 0};
      ok = rzc.randomize() with {sel == 1;};
      `checkd(ok, 1);
      `checkd(rzc.q.size(), 1);
      Check#(bit)::distinct({rzc.x, rzc.q}, `__LINE__);

      rzi.q = '{0, 0, 0};
      ok = rzi.randomize() with {
        q.size() == 1;
        unique {q, x};
      };
      `checkd(ok, 1);
      `checkd(rzi.q.size(), 1);
      Check#(bit)::distinct({rzi.x, rzi.q}, `__LINE__);

      gr.n = 3;
      gr.q = '{0};
      ok = gr.randomize();
      `checkd(ok, 1);
      `checkd(gr.q.size(), 3);
      Check#(bit [1:0])::distinct({gr.x, gr.q}, `__LINE__);

      gr.n = 0;
      gr.q = '{0, 0, 0, 0, 0};
      ok = gr.randomize();
      `checkd(ok, 1);
      `checkd(gr.q.size(), 0);

      // A random size, where only some sizes leave a value for each member
      sr.q = '{0, 0, 0};
      ok = sr.randomize();
      `checkd(ok, 1);
      `checkd(sr.q.size(), 1);
      Check#(bit)::distinct({sr.x, sr.q}, `__LINE__);

      srw.lo = 1;
      srw.hi = 4;
      srw.q = '{};
      ok = srw.randomize();
      `checkd(ok, 1);
      `checkd(srw.q.size() inside {[1:2]}, 1);
      Check#(bit [1:0])::distinct({srw.a, srw.b, srw.q}, `__LINE__);

      srw.q = '{0};
      ok = srw.randomize();
      `checkd(ok, 1);
      `checkd(srw.q.size() inside {[1:2]}, 1);
      Check#(bit [1:0])::distinct({srw.a, srw.b, srw.q}, `__LINE__);

      srw.lo = 2;
      srw.hi = 5;
      srw.q = '{0, 0, 0, 0, 0};
      ok = srw.randomize();
      `checkd(ok, 1);
      `checkd(srw.q.size(), 2);
      Check#(bit [1:0])::distinct({srw.a, srw.b, srw.q}, `__LINE__);

      // No size leaves a value for each member
      srw.lo = 3;
      srw.q = '{0, 0, 0, 0};
      ok = srw.randomize();
      `checkd(ok, 0);

      srm.q = '{'{0, 0}, '{0, 0}, '{0, 0}};
      ok = srm.randomize();
      `checkd(ok, 1);
      `checkd(srm.q.size(), 1);
      Check#(bit [1:0])::distinct({srm.a, srm.q[0][0], srm.q[0][1]}, `__LINE__);

      // Growing, from none and from one element, where only one element fits
      smg.lo = 1;
      smg.q = '{};
      ok = smg.randomize();
      `checkd(ok, 1);
      `checkd(smg.q.size(), 1);
      Check#(bit [1:0])::distinct({smg.a, smg.q[0][0], smg.q[0][1]}, `__LINE__);

      smg.q = '{'{0, 0}};
      ok = smg.randomize();
      `checkd(ok, 1);
      `checkd(smg.q.size(), 1);
      Check#(bit [1:0])::distinct({smg.a, smg.q[0][0], smg.q[0][1]}, `__LINE__);

      // No size leaves a value for each member
      smg.lo = 2;
      smg.q = '{'{0, 0}};
      ok = smg.randomize();
      `checkd(ok, 0);

      // The elements gained are empty, so only the first two elements limit the size
      smd.q = '{'{0, 0, 0}, '{0}};
      ok = smd.randomize();
      `checkd(ok, 1);
      `checkd(smd.q.size(), 1);
      Check#(bit [1:0])::distinct({smd.a, smd.q[0][0], smd.q[0][1], smd.q[0][2]}, `__LINE__);

      smd.q = '{'{0}, '{0}};
      ok = smd.randomize();
      `checkd(ok, 1);
      `checkd(smd.q.size() inside {[1:3]}, 1);
      nibs = '{smd.a};
      foreach (smd.q[i, j]) nibs.push_back(smd.q[i][j]);
      Check#(bit [1:0])::distinct(nibs, `__LINE__);

      wsz.n1 = 2;
      wsz.q1 = '{0, 0, 0};
      wsz.q2 = '{0, 0, 0};
      ok = wsz.randomize();
      `checkd(ok, 1);
      `checkd(wsz.q1.size(), 2);
      `checkd(wsz.q2.size(), 3);
      Check#()::distinct({wsz.q1, wsz.q2}, `__LINE__);

      wfr.q1 = '{0, 0};
      wfr.d = new[2];
      wfr.aa[-3] = 0;
      wfr.aa[7] = 0;
      ok = wfr.randomize();
      `checkd(ok, 1);
      `checkd(wfr.aa.size(), 2);
      Check#()::distinct({wfr.q1, wfr.d, wfr.aa[-3], wfr.aa[7]}, `__LINE__);

      sre.q = '{};
      ok = sre.randomize();
      `checkd(ok, 1);
      `checkd(sre.q.size(), 1);
      Check#(sparse_t)::distinct({sre.x, sre.q}, `__LINE__);
      `checkd(sre.x inside {E_ZERO, E_THREE}, 1);
      `checkd(sre.q[0] inside {E_ZERO, E_THREE}, 1);

      smb.s.q = '{0, 0, 0, 0, 0};
      ok = smb.randomize();
      `checkd(ok, 1);
      `checkd(smb.s.q.size() inside {[1:3]}, 1);
      Check#(bit [1:0])::distinct({smb.x, smb.s.q}, `__LINE__);

      smt.lo = 1;
      smt.s.q = '{0, 0, 0, 0, 0};
      ok = smt.randomize();
      `checkd(ok, 1);
      `checkd(smt.s.q.size() inside {[1:2]}, 1);
      Check#(bit [1:0])::distinct({smt.x, smt.y, smt.s.q}, `__LINE__);

      smt.s.q = '{0};
      ok = smt.randomize();
      `checkd(ok, 1);
      `checkd(smt.s.q.size() inside {[1:2]}, 1);
      Check#(bit [1:0])::distinct({smt.x, smt.y, smt.s.q}, `__LINE__);

      smt.lo = 3;
      smt.s.q = '{0};
      ok = smt.randomize();
      `checkd(ok, 0);

      smm.s.q = '{};
      ok = smm.randomize();
      `checkd(ok, 1);
      `checkd(smm.s.q.size(), 1);
      Check#(bit [1:0])::distinct({smm.x, smm.s.q[0][0], smm.s.q[0][1]}, `__LINE__);

      ok = rsv.randomize();
      `checkd(ok, 1);
      Check#()::distinct({rsv.bvadd, rsv.select}, `__LINE__);
      Check#()::distinct({rsv.bvadd, rsv.concat}, `__LINE__);
      Check#()::distinct({rsv.ite, rsv.distinct}, `__LINE__);

      sri.q = '{5, 5, 5, 5};
      ok = sri.randomize();
      `checkd(ok, 1);
      `checkd(sri.q.size() inside {[1:3]}, 1);
      Check#(int)::distinct({sri.y, sri.q}, `__LINE__);

      ok = sm.randomize();
      `checkd(ok, 1);
      `checkd(sm.none.size(), 0);
      `checkd(sm.one.size(), 1);
      Check#()::distinct({sm.x, sm.one}, `__LINE__);
      Check#()::distinct({sm.y, sm.one}, `__LINE__);

      ok = md.randomize();
      `checkd(ok, 1);
      vals = '{md.x};
      foreach (md.m[i, j]) vals.push_back(md.m[i][j]);
      Check#()::distinct(vals, `__LINE__);

      ok = mdd.randomize();
      `checkd(ok, 1);
      vals = '{mdd.x};
      foreach (mdd.md[i, j]) vals.push_back(mdd.md[i][j]);
      foreach (mdd.mq[i, j]) vals.push_back(mdd.mq[i][j]);
      foreach (mdd.ma[i, j]) vals.push_back(mdd.ma[i][j]);
      `checkd(vals.size(), 7);
      Check#()::distinct(vals, `__LINE__);

      ok = mb.randomize();
      `checkd(ok, 1);
      Check#()::distinct({mb.x, mb.s.arr}, `__LINE__);

      ok = as_.randomize();
      `checkd(ok, 1);
      Check#()::distinct({as_.x, as_.aa["one"], as_.aa["two"], as_.aa["three"]}, `__LINE__);

      st.st = 2'(n);
      st.off = 2'(n + 1);
      st.off.rand_mode(0);
      ok = st.randomize();
      `checkd(ok, 1);
      `checkd(st.st, 2'(n));
      `checkd(st.off, 2'(n + 1));
      Check#(bit [1:0])::distinct({st.st, st.off, st.r}, `__LINE__);

      sta.a = '{7'(n), 7'(n + 20)};
      sta.b = '{7'(n + 40), 7'(n + 60)};
      ok = sta.randomize();
      `checkd(ok, 1);
      `checkd(sta.a[0], 7'(n));
      `checkd(sta.a[1], 7'(n + 20));
      `checkd(sta.b[0], 7'(n + 40));
      `checkd(sta.b[1], 7'(n + 60));
      Check#(bit [6:0])::distinct({sta.a, sta.r}, `__LINE__);

      am.a = '{val_t'(n), val_t'(n + 3), val_t'(n + 5)};
      am.a.rand_mode(0);
      ok = am.randomize();
      `checkd(ok, 1);
      `checkd(am.a[1], val_t'(n + 3));
      Check#()::distinct({am.a, am.b}, `__LINE__);

      ok = cd.randomize() with {sel == 1;};
      `checkd(ok, 1);
      Check#()::distinct({cd.x, cd.q}, `__LINE__);

      ok = ri.randomize();
      `checkd(ok, 1);
      Check#()::distinct({ri.b, ri.arr[ri.i]}, `__LINE__);

      ok = il.randomize() with {unique {il.arr, x};};
      `checkd(ok, 1);
      Check#()::distinct({il.x, il.arr}, `__LINE__);

      ok = std::randomize(sx, sarr) with {unique {sarr, sx};};
      `checkd(ok, 1);
      Check#()::distinct({sx, sarr}, `__LINE__);
    end

    // State arrays sharing a value fail the constraint, and are left as they were
    sta.a = '{1, 2};
    sta.b = '{3, 1};
    ok = sta.randomize();
    `checkd(ok, 0);
    `checkd(sta.a[0], 1);
    `checkd(sta.a[1], 2);
    `checkd(sta.b[0], 3);
    `checkd(sta.b[1], 1);

    // Three members of one bit cannot be distinct after resizing either
    rz.n = 2;
    rz.q = '{0, 0, 0};
    ok = rz.randomize();
    `checkd(ok, 0);

    ok = lg.randomize();
    `checkd(ok, 1);
    lvals = '{lg.x, lg.y};
    foreach (lg.d[i]) lvals.push_back(lg.d[i]);
    Check#(bit [7:0])::distinct(lvals, `__LINE__);
    Check#(bit [7:0])::distinct({lg.big}, `__LINE__);

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
