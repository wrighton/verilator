// DESCRIPTION: Verilator: Rise/fall delays on continuous assigns and gates
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Antmicro
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0x exp=%0x (%s !== %s)\n", `__FILE__, `__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0)
`define check_scalar(exp) do begin `checkh(out_assign, exp); `checkh(out_buf, exp); `checkh(out_net, exp); end while(0)
// verilog_format: on

module t;
  parameter delay = 0;
  localparam int TRI_DELAY = 3;

  logic in = 0;
  logic [3:0] in_vec = 4'h0;
  logic tri_data = 0;
  logic tri_enable = 0;
  wire out_assign;
  wire out_buf;
  wire out_bufif0;
  wire out_bufif1;
  wire out_issue;
  wire out_nmos;
  wire out_notif0;
  wire out_notif1;
  wire out_pmos;
  wire #(5, 3.3) out_net;
  wire [3:0] out_vec_assign;

  assign #(5, 3) out_assign = in;
  buf #(5, 3) u_buf (out_buf, in);
  bufif0 #(delay) u_bufif0 (out_bufif0, in, 1'b0);
  bufif1 #(TRI_DELAY) u_bufif1 (out_bufif1, tri_data, tri_enable);
  bufif1 #(delay) u_issue (out_issue, in, 1'b0);
  nmos #(delay) u_nmos (out_nmos, in, 1'b1);
  notif0 #(delay) u_notif0 (out_notif0, in, 1'b0);
  notif1 #(delay) u_notif1 (out_notif1, in, 1'b1);
  pmos #(delay) u_pmos (out_pmos, in, 1'b0);
  assign out_net = in;
  assign #(5, 3) out_vec_assign = in_vec;

  initial begin
    #4;
    `checkh(out_bufif1, 1'bz);
    tri_enable = 1'b1;
    #2;
    `checkh(out_bufif1, 1'bz);
    #1;
    `checkh(out_bufif1, 1'b0);
    tri_data = 1'b1;
    #2;
    `checkh(out_bufif1, 1'b0);
    #1;
    `checkh(out_bufif1, 1'b1);
    tri_enable = 1'b0;
    #2;
    `checkh(out_bufif1, 1'b1);
    #1;
    `checkh(out_bufif1, 1'bz);
  end

  // Tristate drivers with distinct rise and fall delays (IEEE 1800-2023 28.16)
  logic rf_data = 0;
  logic rf_enable = 0;
  wire rf_bufif1;
  wire rf_bufif1_rfall;
  wire rf_bufif1_rrise;
  wire rf_notif1;
  wire rf_assign;
  bufif1 #(3, 7) u_rf_bufif1 (rf_bufif1, rf_data, rf_enable);
  bufif1 #(3, 7.0) u_rf_bufif1_rfall (rf_bufif1_rfall, rf_data, rf_enable);
  bufif1 #(3.0, 7) u_rf_bufif1_rrise (rf_bufif1_rrise, rf_data, rf_enable);
  notif1 #(3, 7) u_rf_notif1 (rf_notif1, rf_data, rf_enable);
  assign #(7, 3) rf_assign = rf_enable ? rf_data : 1'bz;

  // verilog_format: off
`define check_rf(exp_bufif1, exp_notif1, exp_assign) do begin `checkh(rf_bufif1, exp_bufif1); `checkh(rf_bufif1_rfall, exp_bufif1); `checkh(rf_bufif1_rrise, exp_bufif1); `checkh(rf_notif1, exp_notif1); `checkh(rf_assign, exp_assign); end while(0)
  // verilog_format: on

  initial begin
    #4;
    `check_rf(1'bz, 1'bz, 1'bz);
    // Enabling to drive 0 takes the fall delay, to drive 1 the rise delay
    rf_enable = 1'b1;
    #2;
    `check_rf(1'bz, 1'bz, 1'bz);
    #2;
    `check_rf(1'bz, 1'b1, 1'b0);
    #4;
    `check_rf(1'b0, 1'b1, 1'b0);
    rf_data = 1'b1;
    #2;
    `check_rf(1'b0, 1'b1, 1'b0);
    #2;
    `check_rf(1'b1, 1'b1, 1'b0);
    #4;
    `check_rf(1'b1, 1'b0, 1'b1);
    // Disabling takes the smaller delay
    rf_enable = 1'b0;
    #2;
    `check_rf(1'b1, 1'b0, 1'b1);
    #2;
    `check_rf(1'bz, 1'bz, 1'bz);
    rf_enable = 1'b1;
    #2;
    `check_rf(1'bz, 1'bz, 1'bz);
    #2;
    `check_rf(1'b1, 1'bz, 1'bz);
    #4;
    `check_rf(1'b1, 1'b0, 1'b1);
  end

  initial begin
    #4;
    `check_scalar(1'b0);
    `checkh(out_bufif0, 1'b0);
    `checkh(out_issue, 1'bz);
    `checkh(out_nmos, 1'b0);
    `checkh(out_notif0, 1'b1);
    `checkh(out_notif1, 1'b1);
    `checkh(out_pmos, 1'b0);
    `checkh(out_vec_assign, 4'h0);

    // Rise canceled by a fall before the rise delay expires.
    in = 1'b1;
    #2;
    `check_scalar(1'b0);

    in = 1'b0;
    #4;
    `check_scalar(1'b0);

    // A committed rise.
    in = 1'b1;
    #4;
    `check_scalar(1'b0);
    #1;
    `check_scalar(1'b1);

    // Fall canceled by a new rise before the fall delay expires.
    in = 1'b0;
    #2;
    `check_scalar(1'b1);
    in = 1'b1;
    #4;
    `check_scalar(1'b1);
    #1;
    `check_scalar(1'b1);

    // A committed fall.
    in = 1'b0;
    #2;
    `check_scalar(1'b1);
    #1;
    `check_scalar(1'b0);

    // Whole-value vector rise canceled by a fall back to zero.
    in_vec = 4'h3;
    #2;
    `checkh(out_vec_assign, 4'h0);
    in_vec = 4'h0;
    #4;
    `checkh(out_vec_assign, 4'h0);

    // Zero to nonzero uses the rise delay.
    in_vec = 4'h3;
    #4;
    `checkh(out_vec_assign, 4'h0);
    #1;
    `checkh(out_vec_assign, 4'h3);

    // Nonzero to nonzero still uses the rise delay on the whole value.
    in_vec = 4'h5;
    #4;
    `checkh(out_vec_assign, 4'h3);
    #1;
    `checkh(out_vec_assign, 4'h5);

    // A pending fall back to zero is canceled by a new nonzero value.
    in_vec = 4'h0;
    #2;
    `checkh(out_vec_assign, 4'h5);
    in_vec = 4'h6;
    #4;
    `checkh(out_vec_assign, 4'h5);
    #1;
    `checkh(out_vec_assign, 4'h6);

    // Nonzero to zero uses the fall delay.
    in_vec = 4'h0;
    #2;
    `checkh(out_vec_assign, 4'h6);
    #1;
    `checkh(out_vec_assign, 4'h0);

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
