// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Michael Bedford Taylor
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0x exp=%0x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Release and deassign of a wide variable range in combinational logic
module t;
  logic [199:0] w;
  logic [199:0] a;
  logic en = 0;
  logic [7:0] v = 8'h5a;

  always @* begin
    if (en) force w[47:40] = v;
    else release w[47:40];
  end

  // verilator lint_off IEEEMAYDEPRECATE
  always @* begin
    if (en) assign a[47:40] = v;
    else deassign a[47:40];
  end
  // verilator lint_on IEEEMAYDEPRECATE

  // Releases of disjoint ranges, each reading back only the bits it releases
  logic [95:0] many;
  logic [95:0] manysrc = 96'h0;
  logic [7:0] manyrd;
  assign manyrd = many[23:16];
  initial begin
    for (int i = 0; i < 12; ++i) begin
      case (i)
        0: force many[7:0] = manysrc[7:0];
        1: force many[15:8] = manysrc[15:8];
        2: force many[23:16] = manysrc[23:16];
        default: ;
      endcase
    end
    manysrc = 96'h00_0000_0000_0000_00ab_cdef;
    #1;
    `checkh(manyrd, 8'hab);
    release many[23:16];
    many[23:16] = 8'h5a;
    #1;
    `checkh(manyrd, 8'h5a);
  end

  // A combinational release of a variable whose force reads that variable
  logic [62:0] selfsrc = 63'h0;
  logic selfen = 0;
  wire [62:0] selfw;
  assign selfw = selfsrc;
  // verilator lint_off LATCH
  always @* if (selfen && selfw[0]) release selfw[0];
  // verilator lint_on LATCH

  initial begin
    force selfw = selfw | 63'd1;
    w = '0;
    a = '0;
    #1 en = 1;
    #1 en = 0;
    #1;
    `checkh(w[47:40], 8'h5a);
    `checkh(a[47:40], 8'h5a);
    `checkh(selfw, 63'h1);
    selfsrc = 63'h2;
    #1;
    // Forcing the whole variable hides its continuous driver
    `checkh(selfw, 63'h1);
    selfen = 1;
    #1;
    // Bit 0 released, so it follows the continuous driver again
    `checkh(selfw, 63'h0);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
