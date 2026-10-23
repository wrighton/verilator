// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module sub (
    inout wire [1:0] y
);
endmodule

module sub_var (
    inout var logic [1:0] y  // <--- Warning: variable inout port
);
endmodule

module sub_nonansi (
    y
);
  inout y;
  logic y;  // <--- Warning: variable inout port
endmodule

module t (
    inout [1:0] io
);
  logic [1:0] v;
  sub u_var (.y(v));  // <--- Warning: variable connected

  wire [1:0] w;
  logic [3:0] arr;
  logic [1:0] idx;
  sub u_sel (.y(arr[idx+:2]));  // <--- Warning: variable connected, but not 'idx'
  sub u_cat (.y({w[0], v[0]}));  // <--- Warning: variable connected, but not 'w'
  sub u_net (.y(w));
  sub u_port (.y(io));
  sub_var u_sub_var (.y(w));
  sub_nonansi u_sub_nonansi (.y(w[0]));
endmodule
