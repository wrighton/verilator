// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

typedef struct {logic [1:0] f;} us_t;

interface ifc;
  logic [1:0] s;
endinterface

module sub (
    output logic [1:0] y
);
  assign y = 2'b10;
endmodule

module sub_arr (
    output logic [1:0] y[2]
);
  assign y[0] = 2'b01;
  assign y[1] = 2'b10;
endmodule

module sub_io (
    inout wire [1:0] y
);
endmodule

module t;
  logic [1:0] a, b;
  wire [1:0] c, d;
  sub u_and (.y(a & b));  // <--- Error: not assignable
  sub u_not (.y(~a));  // <--- Error: not assignable
  sub u_cond (.y(a[0] ? a : b));  // <--- Error: not assignable
  sub u_cat_bad (.y({a[0], a[1] | b[1]}));  // <--- Error: not assignable
  sub u_cat_bad2 (.y({~a[0], a[1]}));  // <--- Error: not assignable
  sub u_rep (.y({2{a[0]}}));  // <--- Error: not assignable
  sub_io u_io (.y(c & d));  // <--- Error: not assignable

  // Legal connections
  logic [3:0] v;
  logic [1:0] arr[4];
  logic [1:0] idx;
  us_t us;
  ifc i ();
  sub u_cat (.y({v[0], v[1]}));
  sub u_one (.y({v[3:2]}));
  sub u_sel (.y(v[idx+:2]));
  sub u_elem (.y(arr[idx]));
  sub_arr u_slice (.y(arr[1:2]));
  sub u_stream (.y({<<{a[0], a[1]}}));
  sub u_member (.y(us.f));
  sub u_ifc (.y(i.s));
  sub_io u_io_cat (.y({c[0], d[0]}));
endmodule
