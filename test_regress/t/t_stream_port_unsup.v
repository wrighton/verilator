// DESCRIPTION: Verilator: Verilog Test module
//
// This program is free software; you can redistribute it and/or modify it
// under the terms of either the GNU Lesser General Public License Version 3
// or the Perl Artistic License Version 2.0.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: LGPL-3.0-only OR Artistic-2.0

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
