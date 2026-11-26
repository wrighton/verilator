// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// An output of a hierarchical block that is a function of its data inputs alone, feeding the
// clock gate of another block, so a clock of the model, comes from the combinational update,
// without the clock update of its block in the active region

`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);

module src (
    input clk,
    input [7:0] d,
    output en,
    output [7:0] ft,
    output logic [7:0] r
);
  assign en = d[0];
  assign ft = d ^ 8'h5a;
  always_ff @(posedge clk) r <= r + d;
endmodule

module src_h (
    input clk,
    input [7:0] d,
    output en,
    output [7:0] ft,
    output [7:0] r
);  /*verilator hier_block*/
  src u (.*);
endmodule

// A clock gate, so its enable is a clock input of the block
module gated (
    input clk,
    input en,
    output logic [7:0] cnt
);
  logic en_l;
  always_latch if (!clk) en_l = en;
  wire gclk = clk & en_l;
  always_ff @(posedge gclk) cnt <= cnt + 8'd1;
endmodule

module gated_h (
    input clk,
    input en,
    output [7:0] cnt
);  /*verilator hier_block*/
  gated u (.*);
endmodule

module t;
  localparam realtime STEP = 1ns;
  bit clk;
  bit [7:0] d = 8'h3;
  wire en_h, en_f;
  wire [7:0] ft_h, ft_f, r_h, r_f, cnt_h, cnt_f;
  src_h us_h (clk, d, en_h, ft_h, r_h);
  src us_f (clk, d, en_f, ft_f, r_f);
  gated_h ug_h (clk, en_h, cnt_h);
  gated ug_f (clk, en_f, cnt_f);

  initial begin
    for (int cyc = 0; cyc < 30; ++cyc) begin
      if (cyc % 3 == 0) d = d * 8'd7 + 8'd1;
      #(STEP / 2);
      clk = 1'b1;
      #(STEP / 4);
      `checkh(en_h, en_f);
      `checkh(ft_h, ft_f);
      `checkh(r_h, r_f);
      `checkh(cnt_h, cnt_f);
      #(STEP / 4);
      clk = 1'b0;
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
