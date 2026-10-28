// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Alternative blocks of one conditional generate may share a name, and only the
// selected one may declare the referenced item (IEEE 1800-2023 27.5)

module sub #(
    parameter int V = 0
);
  int v = V;
endmodule

module mid #(
    parameter int P = 1
);
  // if / else if / else, an earlier alternative is selected
  if (P == 0) begin : s
    int a = 10;
  end else if (P == 1) begin : s
    int m = 11;
    for (genvar i = 0; i < 2; ++i) begin : q
      int n = 20 + i;
    end
    sub #(30) c[2] ();
    function automatic int f();
      return 40;
    endfunction
  end else begin : s
    int b = 12;
  end
  // case, with a directly nested if in the last item
  case (P)
    0: begin : k
      int a = 50;
    end
    1: begin : k
      int m = 51;
    end
    default:
    if (P > 5) begin : k
      int b = 52;
    end else begin : k
      int c = 53;
    end
  endcase

  if (P == 1) begin : use1
    int sm = s.m;
    int sqn = s.q[1].n;
    int scv = s.c[1].v;
    int sf = s.f();
    int km = k.m;
  end
  if (P == 0) begin : use0
    int sa = s.a;
    int ka = k.a;
  end
  if (P == 2) begin : use2
    int sb = s.b;
    int kc = k.c;
  end
endmodule

module t;
  mid #(1) u1 ();
  mid #(0) u0 ();
  mid #(2) u2 ();

  initial begin
    #1;
    `checkd(u1.use1.sm, 11);
    `checkd(u1.use1.sqn, 21);
    `checkd(u1.use1.scv, 30);
    `checkd(u1.use1.sf, 40);
    `checkd(u1.use1.km, 51);
    `checkd(u1.s.m, 11);
    `checkd(u1.s.q[0].n, 20);
    `checkd(u0.use0.sa, 10);
    `checkd(u0.use0.ka, 50);
    `checkd(u2.use2.sb, 12);
    `checkd(u2.use2.kc, 53);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
