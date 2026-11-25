// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Many specializations of a module and of an interface, each with its own parameter values, one
// specialization of each of many modules, and a deep recursion of specializations.

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define DISTINCT(n) module distinct``n #(parameter int P = 0) (output int y); assign y = P + n; endmodule
// verilog_format: on

interface ifc #(
    parameter int W = 1
);
  logic [W-1:0] d;
endinterface

module leafi (
    ifc p,
    output int y
);
  assign y = $bits(p.d);
endmodule

module leaf #(
    parameter int P = 0
) (
    output int y
);
  assign y = P;
endmodule

`DISTINCT(0)
`DISTINCT(1)
`DISTINCT(2)
`DISTINCT(3)
`DISTINCT(4)
`DISTINCT(5)
`DISTINCT(6)
`DISTINCT(7)

module recurse #(
    parameter int N = 1
) (
    output int y
);
  if (N > 0) begin : g
    int r;
    recurse #(.N(N - 1)) u (.y(r));
    assign y = N + r;
  end
  else begin : g0
    assign y = 0;
  end
endmodule

module t;
  localparam int N = 50;
  int yp[N];
  int yi[N];
  for (genvar i = 0; i < N; ++i) begin : g
    leaf #(.P(i * 3)) u (.y(yp[i]));
    ifc #(.W(i + 1)) b ();
    leafi ui (
        .p(b),
        .y(yi[i])
    );
  end

  int yd[8];
  distinct0 #(.P(10)) d0 (.y(yd[0]));
  distinct1 #(.P(10)) d1 (.y(yd[1]));
  distinct2 #(.P(10)) d2 (.y(yd[2]));
  distinct3 #(.P(10)) d3 (.y(yd[3]));
  distinct4 #(.P(10)) d4 (.y(yd[4]));
  distinct5 #(.P(10)) d5 (.y(yd[5]));
  distinct6 #(.P(10)) d6 (.y(yd[6]));
  distinct7 #(.P(10)) d7 (.y(yd[7]));
  initial begin
    #1;
    for (int i = 0; i < 8; ++i) `checkd(yd[i], 10 + i);
  end

  int yr;
  recurse #(.N(30)) ur (.y(yr));
  initial begin
    #1;
    `checkd(yr, 465);
  end

  initial begin
    #1;
    for (int i = 0; i < N; ++i) begin
      `checkd(yp[i], i * 3);
      `checkd(yi[i], i + 1);
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
