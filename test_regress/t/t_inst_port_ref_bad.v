// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

typedef struct {logic [1:0] f;} us_t;

module sub (
    ref logic [1:0] r
);
endmodule

module t;
  wire [1:0] w;
  logic [1:0] a, b;
  sub u_net (.r(w));  // <--- Error: net
  sub u_expr (.r(a & b));  // <--- Error: expression
  sub u_const (.r(2'b01));  // <--- Error: expression
  sub u_stream (.r({<<{a}}));  // <--- Error: streaming

  // Legal connections
  logic [1:0] v;
  logic [1:0] arr[2];
  logic idx;
  us_t us;
  sub u_var (.r(v));
  sub u_elem (.r(arr[idx]));
  sub u_member (.r(us.f));
endmodule
