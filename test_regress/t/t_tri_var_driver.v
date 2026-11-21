// DESCRIPTION: Verilator: Tristate net driven through a tristate variable
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0x exp=%0x (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

typedef struct {
  logic [6:0] a;
  int b;
} t_tri_var_driver_us;

module t (
    input clk
);

  int cyc = 0;
  logic [6:0] d1;
  logic [6:0] d2;
  logic en1;
  logic en2;
  always_comb begin
    d1 = 7'(cyc * 5);
    d2 = 7'(cyc * 3 + 1);
    en1 = cyc[0];
    en2 = !cyc[0];
  end

  // A continuous assignment of a z drives z, so another driver of the net wins
  wire [6:0] w_drv;
  assign w_drv = en1 ? d1 : 'z;
  wire [6:0] w_bus;
  assign w_bus = w_drv;
  assign w_bus = en2 ? d2 : 'z;

  logic [6:0] v_drv;
  always_comb
    if (en1) v_drv = d1;
    else v_drv = 'z;
  wire [6:0] v_bus;
  assign v_bus = en2 ? d2 : 'z;
  assign v_bus = v_drv;

  // Through intermediate signals that are not tristate themselves
  wire [6:0] c_mid = {w_drv[2:0], w_drv[6:3]};
  wire [6:0] c_bus;
  assign c_bus = c_mid;
  assign c_bus = en2 ? d2 : 'z;

  logic [6:0] p_mid1;
  logic [6:0] p_mid2;
  always_comb p_mid1 = w_drv;
  always_comb p_mid2 = p_mid1;
  wire [6:0] p_bus;
  assign p_bus = en2 ? d2 : 'z;
  assign p_bus = p_mid2;

  // Through a loop of forwarding assignments
  logic loop_sel;
  always_comb loop_sel = cyc[1];
  // verilator lint_off UNOPTFLAT
  wire [6:0] loop_a;
  wire [6:0] loop_b;
  // verilator lint_on UNOPTFLAT
  assign loop_a = loop_sel ? loop_b : w_drv;
  assign loop_b = loop_a;
  wire [6:0] loop_bus;
  assign loop_bus = loop_b;
  assign loop_bus = en2 ? d2 : 'z;

  // A z read as a condition or operand gives x, not z, so such a driver always drives
  wire [6:0] cond_bus;
  assign (weak0, weak1) cond_bus = 7'h11;
  assign cond_bus = w_drv[0] ? d1 : d2;
  wire [6:0] cmp_bus;
  assign (pull0, pull1) cmp_bus = 7'h11;
  assign cmp_bus = (w_drv === 'z) ? 7'h44 : 7'h22;

  // Through a sign extension, which extends a z sign bit (IEEE 1800-2023 11.8.4)
  wire signed [3:0] s_drv;
  assign s_drv = en1 ? 4'(d1) : 'z;
  wire signed [6:0] s_mid = 7'(s_drv);
  wire [6:0] s_bus;
  assign s_bus = s_mid;
  assign s_bus = en2 ? d2 : 'z;

  // A two-state variable holds a z as 0, so it always drives
  bit [6:0] b_mid;
  assign b_mid = w_drv;
  wire [6:0] b_bus;
  assign (weak0, weak1) b_bus = 7'h11;
  assign b_bus = b_mid;

  // An unpacked struct member, also of an array element
  t_tri_var_driver_us us_mid;
  t_tri_var_driver_us us_arr[2];
  assign us_mid.a = w_drv;
  assign us_arr[1].a = w_drv;
  wire [6:0] us_bus;
  assign us_bus = en2 ? d2 : 'z;
  assign us_bus = us_mid.a;
  wire [6:0] usa_bus;
  assign usa_bus = us_arr[1].a;
  assign usa_bus = en2 ? d2 : 'z;

  // A weaker driver next to a driver of a net that is always driven
  wire [6:0] a_drv;
  assign a_drv = en1 ? d1 : 'z;
  assign a_drv = en2 ? d2 : 'z;
  wire [6:0] a_bus;
  assign (weak0, weak1) a_bus = 7'h11;
  assign a_bus = a_drv;
  logic [6:0] a_mid;
  assign a_mid = a_drv;
  wire [6:0] am_bus;
  assign (weak0, weak1) am_bus = 7'h11;
  assign am_bus = a_mid;

  always @(posedge clk) begin
    cyc <= cyc + 1;
    `checkh(w_bus, en1 ? d1 : d2);
    `checkh(v_bus, en1 ? d1 : d2);
    `checkh(c_bus, en1 ? {d1[2:0], d1[6:3]} : d2);
    `checkh(p_bus, en1 ? d1 : d2);
    if (!loop_sel) `checkh(loop_bus, en1 ? d1 : d2);
    if (en1) `checkh(cond_bus, d1[0] ? d1 : d2);
    `checkh(cmp_bus, en1 ? 7'h22 : 7'h44);
    `checkh(s_bus, en1 ? {{3{d1[3]}}, d1[3:0]} : d2);
    `checkh(b_bus, en1 ? d1 : 7'h00);
    `checkh(us_bus, en1 ? d1 : d2);
    `checkh(usa_bus, en1 ? d1 : d2);
    `checkh(a_bus, en1 ? d1 : d2);
    `checkh(am_bus, en1 ? d1 : d2);
    if (cyc == 10) begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
