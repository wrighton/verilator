// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module t;
  logic clk = 0;
  logic [6:0] d = 0;

  // A chain through blocks with a forceable input, and with a forceable output
  logic [6:0] oi1, qi1, oi2, qi2;
  sub_i ui1 (
      .clk(clk),
      .i(d),
      .o(oi1),
      .q(qi1)
  );
  sub_i ui2 (
      .clk(clk),
      .i(oi1),
      .o(oi2),
      .q(qi2)
  );
  logic [6:0] oo1, qo1, oo2, qo2;
  sub_o uo1 (
      .clk(clk),
      .i(d),
      .o(oo1),
      .q(qo1)
  );
  sub_o uo2 (
      .clk(clk),
      .i(oo1),
      .o(oo2),
      .q(qo2)
  );

  // A block with a forceable input it is also sensitive to, giving an update after the edge
  int cnt, qc = 0;
  sub_c uc (
      .i(d),
      .cnt(cnt)
  );
  always @(posedge clk) qc <= cnt;

  // A chain through a block forcing a variable in code from its inputs
  logic fe = 0;
  logic [6:0] fv = 0;
  logic [6:0] of1, qf1, qf2;
  sub_f uf1 (
      .clk(clk),
      .fe(fe),
      .fv(fv),
      .i(d),
      .o(of1),
      .q(qf1)
  );
  sub_i uf2 (
      .clk(clk),
      .i(of1),
      .o(),
      .q(qf2)
  );

  // A block with a forceable clock
  logic [6:0] qk;
  sub_k uk (
      .clk(clk),
      .i(d),
      .q(qk)
  );

  // A clock through a block with a forceable input
  logic [6:0] co, qz;
  sub_p up (
      .i({6'b0, clk}),
      .o(co)
  );
  sub_i uz (
      .clk(co[0]),
      .i(d),
      .o(),
      .q(qz)
  );

  initial begin
    #1;
    repeat (3) begin
      d = d + 7'h25;
      fv = fv + 7'h13;
      fe = ~fe;
      // The clock edge follows the change of d through each chain
      #0 clk = 1;
      #1;
      `checkh(qi1, d);
      `checkh(qi2, d);
      `checkh(qo1, d);
      `checkh(qo2, d);
      `checkh(qc, cnt - 1);
      `checkh(qf2, of1);
      `checkh(qk, d);
      `checkh(qz, d);
      clk = 0;
      #1;
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule

module sub_i (
    input logic clk,
    input logic [6:0] i  /*verilator forceable*/,
    output logic [6:0] o,
    output logic [6:0] q
);
  /*verilator hier_block*/
  assign o = i;
  always @(posedge clk) q <= i;
endmodule

module sub_o (
    input logic clk,
    input logic [6:0] i,
    output logic [6:0] o  /*verilator forceable*/,
    output logic [6:0] q
);
  /*verilator hier_block*/
  assign o = i;
  always @(posedge clk) q <= i;
endmodule

module sub_c (
    input logic [6:0] i  /*verilator forceable*/,
    output int cnt
);
  /*verilator hier_block*/
  initial cnt = 0;
  always @(i) cnt <= cnt + 1;
endmodule

module sub_f (
    input logic clk,
    input logic fe,
    input logic [6:0] fv,
    input logic [6:0] i,
    output logic [6:0] o,
    output logic [6:0] q
);
  /*verilator hier_block*/
  logic [6:0] w  /*verilator forceable*/;
  assign w = i;
  always @* if (fe) force w = fv; else release w;
  assign o = w;
  always @(posedge clk) q <= w;
endmodule

module sub_k (
    input logic clk  /*verilator forceable*/,
    input logic [6:0] i,
    output logic [6:0] q
);
  /*verilator hier_block*/
  always @(posedge clk) q <= i;
endmodule

module sub_p (
    input logic [6:0] i  /*verilator forceable*/,
    output logic [6:0] o
);
  /*verilator hier_block*/
  assign o = i;
endmodule
