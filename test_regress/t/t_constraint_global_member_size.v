// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0x exp=%0x (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

// The constraints of a rand member object on the elements of its rand array of class handles
// are solved with those of the containing object constraining the array's size (IEEE 1800-2023
// 18.5.8)

class Entry;
  rand bit bos;
  rand bit [7:0] x;
endclass

class Mpls;
  rand Entry stack[$];
  constraint c_size {stack.size() <= 2;}
  constraint c_bos {
    foreach (stack[ii]) {
      if (ii == (stack.size() - 1)) stack[ii].bos == 1'b1;
      else stack[ii].bos == 1'b0;
    }
  }
  function void pre_randomize();
    stack.delete();
    repeat (50) begin
      Entry e = new;
      stack.push_back(e);
    end
  endfunction
endclass

class Trn;
  rand int unsigned hdrSize;
  rand Mpls mpls;
  constraint c_hdr {
    hdrSize <= 8;
    hdrSize % 4 == 0;
    mpls.stack.size() == hdrSize / 4;
  }
  function new();
    mpls = new;
  endfunction
endclass

class Ordered;  // Elements in increasing order, the array grown by the containing object
  rand Entry arr[];
  constraint c_size {arr.size() inside {[2 : 3]};}
  constraint c_order {foreach (arr[i]) if (i > 0) arr[i].x > arr[i-1].x;}
  function void pre_randomize();
    arr = new[3];
    foreach (arr[i]) arr[i] = new;
  endfunction
endclass

class Grower;
  rand int unsigned n;
  rand Ordered ordered;
  constraint c_n {
    ordered.arr.size() == n;
    n inside {[2 : 3]};
  }
  function new();
    ordered = new;
  endfunction
endclass

class Indexed;  // Elements selected by a rand index keep the member's own randomize()
  rand Entry q[$];
  rand int ix;
  constraint c_size {q.size() inside {[1 : 3]};}
  constraint c_ix {
    ix == 0;
    q[ix].x == 8'd17;
    q[ix].bos == 1'b1;
  }
  function void pre_randomize();
    q.delete();
    repeat (3) begin
      Entry e = new;
      q.push_back(e);
    end
  endfunction
endclass

class IndexedHolder;
  rand Indexed indexed;
  constraint c_outer {indexed.q.size() == 2;}
  function new();
    indexed = new;
  endfunction
endclass

class MemberIndexed;  // Elements selected by non-rand members keep the member's own randomize()
  rand Entry q[$];
  int idx = 0;
  int idx2 = 1;
  constraint c_size {q.size() == 2;}
  constraint c_order {q[idx].x < q[idx2].x;}
  function void pre_randomize();
    q.delete();
    repeat (2) begin
      Entry e = new;
      q.push_back(e);
    end
  endfunction
endclass

class Mixed;  // A select by a rand index with one by a constant keeps the own randomize()
  rand Entry q[$];
  rand int ix;
  static int sidx = 0;
  constraint c_size {q.size() inside {[1 : 3]};}
  constraint c_mixed {
    ix == 0;
    q[ix].x == 8'd17;
    q[0].bos == 1'b1;
  }
  constraint c_static {q[sidx].x != 8'd18;}  // Also a static index
  function void pre_randomize();
    q.delete();
    repeat (3) begin
      Entry e = new;
      q.push_back(e);
    end
  endfunction
endclass

class MixedHolder;
  rand Mixed mixed;
  constraint c_outer {mixed.q.size() == 2;}
  function new();
    mixed = new;
  endfunction
endclass

class Fixed;  // A select by a member index with foreach selects keeps the own randomize()
  rand Entry q[$];
  int fix = 1;
  constraint c_size {q.size() == 3;}
  constraint c_fix {
    foreach (q[i]) q[i].x < 8'd200;
    q[fix].x == 8'd123;
  }
  function void pre_randomize();
    q.delete();
    repeat (3) begin
      Entry e = new;
      q.push_back(e);
    end
  endfunction
endclass

class FixedHolder;
  rand Fixed fixed;
  rand bit [7:0] k;
  constraint c_k {k == 8'd5;}
  function new();
    fixed = new;
  endfunction
endclass

class MemberIndexedHolder;
  rand MemberIndexed memberIndexed;
  rand bit [7:0] k;
  constraint c_k {k > 0;}
  function new();
    memberIndexed = new;
  endfunction
endclass

class Ordered2;  // Selects by two expressions of a foreach index, sized by another class
  rand Entry q[$];
  constraint c_q {foreach (q[i]) if (i < q.size() - 2) q[i+1].x < q[i+2].x;}
  function void pre_randomize();
    q.delete();
    repeat (6) begin
      Entry e = new;
      q.push_back(e);
    end
  endfunction
endclass

class Ordered2Holder;
  rand Ordered2 o;
  rand int unsigned n;
  constraint c_n {
    n inside {[3 : 5]};
    o.q.size() == n;
  }
  function new();
    o = new;
  endfunction
endclass

class Limited;  // Its elements' constraint reads another array's size, not their array's
  rand Entry q[$];
  int lim[$] = '{1, 2, 3, 4, 5, 6, 7, 8, 9, 10};
  int fix = 0;
  constraint c_q {
    foreach (q[i]) q[i].x < 8'(lim.size());
    q[fix].x == 8'd7;
  }
  function void pre_randomize();
    q.delete();
    repeat (6) begin
      Entry e = new;
      q.push_back(e);
    end
  endfunction
endclass

class LimitedHolder;
  rand Limited l;
  rand int unsigned n;
  constraint c_n {
    n inside {[1 : 4]};
    l.q.size() == n;
  }
  function new();
    l = new;
  endfunction
endclass

module t;
  Trn trn;
  Grower grower;
  IndexedHolder indexedHolder;
  MemberIndexedHolder memberIndexedHolder;
  MixedHolder mixedHolder;
  Ordered2Holder ordered2Holder;
  LimitedHolder limitedHolder;
  FixedHolder fixedHolder;
  int ok;
  initial begin
    trn = new;
    grower = new;
    indexedHolder = new;
    memberIndexedHolder = new;
    mixedHolder = new;
    ordered2Holder = new;
    limitedHolder = new;
    fixedHolder = new;
    repeat (20) begin
      ok = trn.randomize();
      `checkh(ok, 1);
      `checkh(trn.mpls.stack.size() <= 2, 1'b1);
      `checkh(trn.mpls.stack.size(), trn.hdrSize / 4);
      foreach (trn.mpls.stack[i]) `checkh(trn.mpls.stack[i].bos, i == trn.mpls.stack.size() - 1);
      ok = grower.randomize();
      `checkh(ok, 1);
      `checkh(grower.ordered.arr.size(), grower.n);
      foreach (grower.ordered.arr[i]) begin
        if (i > 0) `checkh(grower.ordered.arr[i].x > grower.ordered.arr[i-1].x, 1'b1);
      end
      ok = indexedHolder.randomize();
      `checkh(ok, 1);
      `checkh(indexedHolder.indexed.q.size(), 2);
      `checkh(indexedHolder.indexed.q[0].x, 8'd17);
      `checkh(indexedHolder.indexed.q[0].bos, 1'b1);
      ok = limitedHolder.randomize();
      `checkh(ok, 1);
      `checkh(limitedHolder.l.q.size(), limitedHolder.n);
      `checkh(limitedHolder.l.q[0].x, 8'd7);
      foreach (limitedHolder.l.q[i]) `checkh(limitedHolder.l.q[i].x < 8'd10, 1'b1);
      ok = ordered2Holder.randomize();
      `checkh(ok, 1);
      `checkh(ordered2Holder.o.q.size(), ordered2Holder.n);
      for (int i = 0; i < int'(ordered2Holder.o.q.size()) - 2; ++i)
        `checkh(ordered2Holder.o.q[i+1].x < ordered2Holder.o.q[i+2].x, 1'b1);
      ok = mixedHolder.randomize();
      `checkh(ok, 1);
      `checkh(mixedHolder.mixed.q.size(), 2);
      `checkh(mixedHolder.mixed.q[0].x, 8'd17);
      `checkh(mixedHolder.mixed.q[0].bos, 1'b1);
      ok = fixedHolder.randomize();
      `checkh(ok, 1);
      `checkh(fixedHolder.k, 8'd5);
      `checkh(fixedHolder.fixed.q.size(), 3);
      `checkh(fixedHolder.fixed.q[1].x, 8'd123);
      foreach (fixedHolder.fixed.q[i]) `checkh(fixedHolder.fixed.q[i].x < 8'd200, 1'b1);
      ok = memberIndexedHolder.randomize();
      `checkh(ok, 1);
      `checkh(memberIndexedHolder.memberIndexed.q.size(), 2);
      `checkh(memberIndexedHolder.memberIndexed.q[0].x < memberIndexedHolder.memberIndexed.q[1].x,
              1'b1);
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
