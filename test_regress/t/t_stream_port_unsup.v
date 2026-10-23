// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;

  logic [7:0] a;
  logic [15:0] b;
  int n;

  sub_q u_q (.p({>>{a, b}}), .n(n));
  sub_dyn u_dyn (.p({<<8{a, b}}));
  sub_out u_out (.p({>>{a, b}}));

endmodule

typedef byte bq_t[$];

module sub_q (
    input bq_t p,
    output int n
);
  assign n = p.size();
endmodule

module sub_dyn (
    input byte p[]
);
endmodule

module sub_out (
    output byte p[$]
);
endmodule
