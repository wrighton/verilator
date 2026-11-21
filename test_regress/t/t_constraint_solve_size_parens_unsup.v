// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

class Inner;
  rand bit [6:0] arr[];
endclass

class Holder;
  rand Inner objects[2];
endclass

typedef struct {rand bit [6:0] q[$];} st_t;

class C;
  rand bit [6:0] n;
  rand bit [6:0] dd[][];
  rand st_t st;
  rand bit [6:0] fa[3];
  bit [6:0] nd[];
  rand Inner in;
  rand Holder h;
  rand bit [6:0] q[$];
  constraint c {
    solve n before dd[1].size();
    solve n before st.q.size();
    solve st.q.size() before n;
    solve n before h.objects[0].arr.size();
    solve h.objects[1].arr.size() before n;
    solve n before q[$];
    disable soft q[$];
    disable soft fa[1];
    disable soft nd.size();
    n > 0 -> disable soft fa[2];
  }
endclass

module t;
  initial begin
    automatic C c = new;
    void'(c.randomize());
  end
endmodule
