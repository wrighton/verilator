// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Except for its event control, the expressions of an always_ff in a checker are sampled, also
// in its immediate and deferred assertions (IEEE 1800-2023 17.5). An automatic variable is read
// with its current value (IEEE 1800-2023 16.5.1).
checker c_s (logic clk, logic d, logic [1:0] v);
  logic q = 0;
  logic qf = 0;
  logic [1:0] r = 0;
  logic qs = 0;
  logic qp = 0;
  int nfail = 0;
  int nfinal = 0;
  function automatic logic inv(logic x);
    return !x;
  endfunction
  function void count_final();
    ++nfinal;
  endfunction
  always_ff @(posedge clk) begin
    q <= d;
    qs <= $sampled(d);
    qp <= $past(d);
    qf <= inv(d);
    if (d) r <= 2'b11;
    else for (int i = 0; i < 2; i++) r[i] <= v[1 - i];
    a_d : assert (!d)
    else nfail <= nfail + 1;
    a_f : assert final (!d)
    else count_final();
  end
endchecker

// A variable of the event control is read with its current value (IEEE 1800-2023 17.5 example)
checker c_ev (logic clk, logic rst, logic b, logic c);
  logic z = 0;
  always_ff @(posedge clk or negedge rst) begin
    if (rst) z <= b;
    else z <= !c;
  end
endchecker

// Also with the event control as the first statement
checker c_ev_stmt (logic clk, logic rst, logic b);
  logic z = 0;
  always_ff begin
    @(posedge clk or negedge rst);
    if (rst) z <= b;
    else z <= 1'b1;
  end
endchecker

module t;
  logic clk = 0;
  logic d = 0;
  logic [1:0] v = 2'b01;
  c_s u (clk, d, v);
  initial begin
    // In the time step of the first edge, after it: the sampled values are d = 0, v = 'b01
    #5 clk = 1'b1;
    d = 1'b1;
    v = 2'b10;
    #1;
    `checkh(u.q, 1'b0);
    `checkh(u.qs, 1'b0);
    `checkh(u.qf, 1'b1);
    `checkh(u.r, 2'b10);
    `checkh(u.nfail, 0);
    `checkh(u.nfinal, 0);
    // At the second edge the sampled value of d is 1
    #4 clk = 1'b0;
    #5 clk = 1'b1;
    #1;
    `checkh(u.q, 1'b1);
    `checkh(u.qs, 1'b1);
    `checkh(u.qp, 1'b0);
    `checkh(u.qf, 1'b0);
    `checkh(u.r, 2'b11);
    `checkh(u.nfail, 1);
    `checkh(u.nfinal, 1);
    #10;
    $write("*-* All Finished *-*\n");
    $finish;
  end

  logic ev_clk = 0;
  logic rst = 1;
  logic b = 0;
  logic c = 0;
  c_ev u_ev (ev_clk, rst, b, c);
  c_ev_stmt u_ev_stmt (ev_clk, rst, b);
  initial begin
    // At the negedge of rst the current rst is 0, and the sampled c is 0
    #5 rst = 1'b0;
    b = 1'b1;
    c = 1'b1;
    #1;
    `checkh(u_ev.z, 1'b1);
    `checkh(u_ev_stmt.z, 1'b1);
    // At a clock edge the current rst is 1, and the sampled b is 0
    #4 rst = 1'b1;
    b = 1'b0;
    #5 ev_clk = 1'b1;
    b = 1'b1;
    #1;
    `checkh(u_ev.z, 1'b0);
  end
endmodule
