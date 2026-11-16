// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Too large, and too many instances, to inline everywhere
module big (
    input clk,
    input [31:0] in,
    output logic [31:0] out
);
  logic [31:0] a, b, c, d;
  always_ff @(posedge clk) begin
    a <= (in ^ 32'h12345678) + (in << 3);
    b <= (a >> 5) - (a ^ 32'h55aa55aa) + (in & 32'hff00ff00);
    c <= (b * 3) ^ (a | b) ^ (in + a + b);
    d <= (c - a) ^ (b + in) ^ {a[7:0], c[31:8]} ^ (d >> 3);
    out <= d + c + (b << 1) - (a >> 2) + (c ^ in) + {c[15:0], b[31:16]};
  end
endmodule

// Small part of the design, so flattened: its instance of 'big' is inlined, the others are not
module sub (
    input clk,
    input [31:0] in,
    output [31:0] out
);
  big u_big (
      .clk,
      .in,
      .out
  );
endmodule

module t (
    input clk
);
  int cyc = 0;

  logic [31:0] outs[24];
  for (genvar i = 0; i < 24; ++i) begin : g
    big u_big (
        .clk,
        .in(cyc + i),
        .out(outs[i])
    );
  end

  logic [31:0] subOut;
  sub u_sub (
      .clk,
      .in(cyc),
      .out(subOut)
  );

  logic [31:0] lastOut = 0;
  always @(posedge clk) begin
    cyc <= cyc + 1;
    if (cyc > 16) begin
      `checkh(subOut, outs[0]);
      if (subOut == lastOut) `stop;
      lastOut <= subOut;
    end
    if (cyc == 30) begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
