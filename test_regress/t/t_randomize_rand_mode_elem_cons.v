// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// The objects of array elements with rand_mode off are not randomized, so their own
// constraints do not apply (IEEE 1800-2023 18.8), also when the array is solved with the
// constraints of its container

typedef struct {int W;} param_t;

class Strb #(
    parameter param_t P = '{W: 8}
);
  rand bit [P.W-1:0] strb;
  rand bit last;
  constraint c_strb {strb < 3;}
  constraint c_soft {soft strb == 8'd1;}  // Stays soft
endclass

typedef Strb#('{W: 8}) strb_t;

class Trans;
  rand strb_t m_wstrb[];
  int n = 3;
  int frozen = 2;  // Elements i % frozen == 0 have rand_mode off
  constraint c_last {
    foreach (m_wstrb[i]) {
      m_wstrb[i].last == (i == n - 1);
      m_wstrb[i].strb != 8'd1;
    }
  }
  function void pre_randomize();
    m_wstrb = new[n];
    foreach (m_wstrb[i]) begin
      m_wstrb[i] = new;
      m_wstrb[i].strb = 8'hf0;  // Violates c_strb
      m_wstrb[i].last = (i == n - 1);
      m_wstrb[i].rand_mode(i % frozen != 0);
    end
  endfunction
endclass

class Item;
  rand bit [6:0] v;
  constraint c_v {v[0] == 1'b1;}
endclass

class Holder;
  rand Item a[];
  function new();
    a = new[3];
    foreach (a[i]) a[i] = new;
  endfunction
endclass

class Outer;
  rand Holder h;
  constraint c_o {foreach (h.a[i]) h.a[i].v < 7'd50;}
  function new();
    h = new;
  endfunction
endclass

module t;
  task automatic test_trans;
    Trans tr = new;
    int randomize_result;
    for (int k = 1; k < 6; ++k) begin
      tr.n = k;
      tr.frozen = (k % 2) + 1;  // Every second one frozen, then all
      randomize_result = tr.randomize();
      `checkd(randomize_result, 1);
      `checkd(tr.m_wstrb.size(), k);
      foreach (tr.m_wstrb[i]) begin
        `checkd(tr.m_wstrb[i].last, i == k - 1);
        if (i % tr.frozen == 0) `checkd(tr.m_wstrb[i].strb, 8'hf0)
        else `checkd(tr.m_wstrb[i].strb inside {8'd0, 8'd2}, 1'b1)
      end
    end
  endtask

  task automatic test_member_array;
    Outer o = new;
    int randomize_result;
    o.h.a[1].v = 7'd20;  // Violates c_v, satisfies c_o
    o.h.a[1].rand_mode(0);
    repeat (10) begin
      randomize_result = o.randomize();
      `checkd(randomize_result, 1);
      `checkd(o.h.a[1].v, 7'd20);
      `checkd(o.h.a[0].v[0], 1'b1);
      `checkd(o.h.a[2].v[0], 1'b1);
      `checkd(o.h.a[0].v < 7'd50, 1'b1);
    end
  endtask

  initial begin
    test_trans();
    test_member_array();
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
