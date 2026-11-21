// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain, for
// any use, without warranty, 2026 by Antmicro.
// SPDX-FileCopyrightText: 2026 Antmicro
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0)

`define IMPURE_ONE |($random | $random)
// verilog_format: on

interface force_cond_if;
  logic [6:0] sig;
endinterface

module force_cond_leaf (
    input logic [6:0] port
);
endmodule

module t;
  reg [1:0] a = 2;
  bit [1:0] b = 1;
  bit [1:0] c = 0;

  initial begin
    force a = b;
    if (`IMPURE_ONE == 1) force a = c;
    if (`IMPURE_ONE == 0) force a = b;
    c = 3;
    b = 2;
    #1;
    `checkh(a, 3);
    if (`IMPURE_ONE == 1) force a = b;
    if (`IMPURE_ONE == 0) force a = c;
    c = 2;
    b = 1;
    #1;
    `checkh(a, 1);
    #1 $finish;
  end

  // Test: two variables forced in either direction, chosen at run time
  logic [6:0] fwd_x = 7'h11;
  logic [6:0] fwd_y = 7'h22;
  logic [6:0] rev_x = 7'h33;
  logic [6:0] rev_y = 7'h44;
  wire [6:0] fwd_x_rd = fwd_x;
  wire [6:0] rev_y_rd = rev_y;
  initial begin
    if (`IMPURE_ONE == 1) force fwd_x = fwd_y;
    else force fwd_y = fwd_x;
    if (`IMPURE_ONE == 0) force rev_x = rev_y;
    else force rev_y = rev_x;
    #1;
    `checkh(fwd_x, 7'h22);
    `checkh(fwd_x_rd, 7'h22);
    `checkh(rev_y, 7'h33);
    `checkh(rev_y_rd, 7'h33);
    fwd_y = 7'h55;
    rev_x = 7'h66;
    #1;
    `checkh(fwd_x, 7'h55);
    `checkh(fwd_x_rd, 7'h55);
    `checkh(rev_y, 7'h66);
    `checkh(rev_y_rd, 7'h66);
  end

  // Test: an interface signal and a port forced in either direction, chosen at run time
  force_cond_if fwd_if ();
  force_cond_if rev_if ();
  logic [6:0] fwd_src = 7'h11;
  logic [6:0] rev_src = 7'h22;
  force_cond_leaf fwd_leaf (.port(fwd_src));
  force_cond_leaf rev_leaf (.port(rev_src));
  initial begin
    fwd_if.sig = 7'h33;
    rev_if.sig = 7'h44;
    if (`IMPURE_ONE == 1) force fwd_if.sig = fwd_leaf.port;
    else force fwd_leaf.port = fwd_if.sig;
    if (`IMPURE_ONE == 0) force rev_if.sig = rev_leaf.port;
    else force rev_leaf.port = rev_if.sig;
    #1;
    `checkh(fwd_if.sig, 7'h11);
    `checkh(rev_leaf.port, 7'h44);
    fwd_src = 7'h55;
    rev_if.sig = 7'h66;
    #1;
    `checkh(fwd_if.sig, 7'h55);
    `checkh(rev_leaf.port, 7'h66);
  end

  // Test: forces on disjoint bits or elements, each read from the same variable
  logic [6:0] disj = 7'h0c;
  logic [6:0] disj_mem[1:4] = '{7'h1, 7'h2, 7'h3, 7'h4};
  initial begin
    force disj[0] = disj[2];
    force disj[1] = disj[3];
    force disj_mem[1] = disj_mem[2];
    force disj_mem[3] = disj_mem[4];
    #1;
    `checkh(disj, 7'h0f);
    `checkh(disj_mem[1], 7'h2);
    `checkh(disj_mem[3], 7'h4);
    disj = 7'h48;
    disj_mem[2] = 7'h55;
    disj_mem[4] = 7'h66;
    #1;
    `checkh(disj, 7'h4a);
    `checkh(disj_mem[1], 7'h55);
    `checkh(disj_mem[3], 7'h66);
  end

  // Test: a combinational write of one bit from another, with an unrelated bit forced.
  // The process reading and writing the variable is an ordinary cycle, forced or not.
  bit ff_clk = 0;
  // verilator lint_off UNOPTFLAT
  bit [6:0] ff_var;
  // verilator lint_on UNOPTFLAT
  always @* ff_var[0] = ff_var[1];
  always @(posedge ff_clk) ff_var[1] = 1'b1;
  initial force ff_var[2] = 1'b1;
  initial begin
    #1 ff_clk = 1'b1;
    #1;
    `checkh(ff_var[2:0], 3'b111);
  end

endmodule
