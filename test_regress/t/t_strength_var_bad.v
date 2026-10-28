// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module sub (
    output o_net,
    output wire [1:0] o_wire,
    output logic o_logic,  // Variable, as has a data type
    output reg o_reg,  // Variable
    output var o_var,  // Variable
    inout logic io_logic  // Net, as is an inout
);
  assign (strong0, weak1) o_net = 1'b1;  // OK
  assign (weak0, weak1) o_wire = 2'b11;  // OK
  assign (strong0, weak1) o_logic = 1'b1;  // Bad
  assign (strong0, weak1) o_reg = 1'b1;  // Bad
  assign (strong0, weak1) o_var = 1'b1;  // Bad
  assign (weak0, weak1) io_logic = 1'b1;  // OK
endmodule

module t;
  logic v;
  reg r;
  wire w;
  wire wd;
  wire (strong0, pull1) wdecl = 1'b1;  // OK

  assign (strong0, weak1) v = 1'b1;  // Bad
  assign (strong0, weak1) {w, r} = 2'b11;  // Bad on 'r'
  buf (strong0, weak1) u_buf (wd, 1'b1);  // OK
  logic vg;
  buf (strong0, weak1) u_bufv (vg, 1'b1);  // Bad

  wire o_net, o_logic, o_reg, o_var, io_logic;
  wire [1:0] o_wire;
  sub u_sub (.*);
endmodule
