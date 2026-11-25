// DESCRIPTION: Verilator: Verilog Test module
//
// A dynamic array or queue streamed into a wider packed variable is
// left-justified, zero-filled on the right, with '<<' reversing the blocks of
// the stream itself (IEEE 1800-2023 11.4.14).
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module t;
  initial begin
    byte unsigned dyn8[];
    bit [3:0] q4[$];
    bit [39:0] p40;
    bit [99:0] p100;
    bit [26:0] p27;
    for (int i = 0; i < 2; ++i) begin
      dyn8 = '{8'h33 + 8'(i), 8'h44, 8'h55};
      q4 = '{4'h1 + 4'(i), 4'h2, 4'h3};
      p40 = {>>{dyn8}};
      `checkh(p40, {8'h33 + 8'(i), 32'h44550000});
      p40 = {<<8{dyn8}};
      `checkh(p40, {16'h5544, 8'h33 + 8'(i), 16'h0});
      p40 = {<<16{dyn8}};  // The leftmost block is shorter
      `checkh(p40, {16'h4455, 8'h33 + 8'(i), 16'h0});
      p100 = {<<8{dyn8}};
      `checkh(p100, {16'h5544, 8'h33 + 8'(i), 76'h0});
      p27 = {>>{q4}};
      `checkh(p27, {4'h1 + 4'(i), 8'h23, 15'h0});
      p27 = {<<8{q4}};
      `checkh(p27, {8'h23, 4'h1 + 4'(i), 15'h0});
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
