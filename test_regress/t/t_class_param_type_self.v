// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Type parameter values that refer to the class specialization they are a value of, through a
// class handle, so are of finite size

class C #(
    type T = int
);
  T v;
  int id;
endclass

interface Sink #(
    type T = int
);
  T v;
endinterface

// Through a queue
typedef Q;
typedef C#(Q) Q[$];
// Through a struct member
typedef struct M;
typedef struct {C #(M) h;} M;
// Directly
typedef D;
typedef C#(D) D;
// Through a struct passed to an interface
typedef struct S;
typedef struct {C #(S) h;} S;

module t;
  Sink #(.T(S)) snk ();

  initial begin
    begin
      automatic Q q;
      // Also the same specialization when written again
      automatic C #(Q) c = new;
      c.id = 1;
      q.push_back(c);
      q[0].v.push_back(c);
      `checkd(q[0].v[0].id, 1);
    end
    begin
      automatic M m;
      m.h = new;
      m.h.id = 2;
      m.h.v.h = m.h;
      `checkd(m.h.v.h.id, 2);
    end
    begin
      automatic D d = new;
      d.id = 3;
      d.v = d;
      `checkd(d.v.v.id, 3);
    end
    begin
      snk.v.h = new;
      snk.v.h.id = 4;
      snk.v.h.v = snk.v;
      `checkd(snk.v.h.v.h.id, 4);
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
