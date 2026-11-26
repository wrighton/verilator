// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Ports of a hierarchical block named like the signals and arguments its wrapper adds

`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);

module sub (
    input settled__V,
    input [7:0] combo_seqnum__V,
    input [7:0] last_combo_seqnum__V,
    output logic [7:0] q,
    output [7:0] o
);
  initial q = 8'h5;
  always @(posedge settled__V) q <= q + combo_seqnum__V;
  assign o = q ^ last_combo_seqnum__V;
endmodule

module sub_h (
    input settled__V,
    input [7:0] combo_seqnum__V,
    input [7:0] last_combo_seqnum__V,
    output [7:0] q,
    output [7:0] o
);  /*verilator hier_block*/
  sub u (.*);
endmodule

module t;
  localparam realtime STEP = 1ns;
  bit clk;
  bit [7:0] d = 8'h3;
  bit [7:0] e = 8'h60;
  wire [7:0] q_h, q_f, o_h, o_f;
  sub_h u_h (clk, d, e, q_h, o_h);
  sub u_f (clk, d, e, q_f, o_f);
  initial begin
    #(STEP / 2);
    `checkh(q_h, 8'h5);
    for (int cyc = 0; cyc < 4; ++cyc) begin
      clk = 1'b1;
      #(STEP / 2);
      `checkh(q_h, q_f);
      `checkh(o_h, o_f);
      clk = 1'b0;
      e = e + 8'h1;
      #(STEP / 2);
      `checkh(q_h, q_f);
      `checkh(o_h, o_f);
    end
    `checkh(q_h, 8'h11);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
