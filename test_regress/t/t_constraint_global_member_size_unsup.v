// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Constrains elements by the size of their array, which another class's constraint sizes, so
// the member's constraints are solved with it, cloned, which reports its select by a non-rand
// member unsupported
class Last;
  rand bit b;
endclass

class Fixed;
  rand Last st[$];
  int fix = 0;
  constraint c_st {
    foreach (st[i]) st[i].b == (i == st.size() - 1);
    st[fix].b == (st.size() == 1);
  }
endclass

class FixedHolder;
  rand Fixed f;
  rand int unsigned n;
  constraint c_n {
    n inside {[1 : 4]};
    f.st.size() == n;
  }
  function new();
    f = new;
  endfunction
endclass

// Likewise, its select by an index of the size
class Ending;
  rand Last st[$];
  constraint c_st {st[st.size() - 1].b == 1;}
endclass

class EndingHolder;
  rand Ending e;
  rand int unsigned n;
  constraint c_n {
    n inside {[1 : 4]};
    e.st.size() == n;
  }
  function new();
    e = new;
  endfunction
endclass

// Likewise, its select by an index of the size it solves itself
class Sized;
  rand Last st[$];
  constraint c_st {
    st.size() == 3;
    st[st.size() - 1].b == 1;
  }
endclass

class SizedHolder;
  rand Sized s;
  rand bit k;
  constraint c_k {k == 1;}
  function new();
    s = new;
  endfunction
endclass

// Likewise, its select of the last element, whose size it solves
class Back;
  rand Last st[$];
  constraint c_st {
    st.size() == 3;
    st[$].b == 1;
  }
endclass

class BackHolder;
  rand Back b;
  rand bit k;
  constraint c_k {k == 1;}
  function new();
    b = new;
  endfunction
endclass

module t;
  FixedHolder fixedHolder;
  EndingHolder endingHolder;
  SizedHolder sizedHolder;
  BackHolder backHolder;
  int ok;
  initial begin
    fixedHolder = new;
    endingHolder = new;
    sizedHolder = new;
    backHolder = new;
    ok = fixedHolder.randomize();
    ok = endingHolder.randomize();
    ok = sizedHolder.randomize();
    ok = backHolder.randomize();
    $finish;
  end
endmodule
