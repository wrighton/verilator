// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

`timescale 1ns / 1ns

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module t;
  // Combinational logic reading the sampled time changes with the variables it reads, not with
  // the time (IEEE 1800-2023 9.2.2.2.1)
  time t_plain, t_sampled, y, z, w;
  logic [7:0] a = 0;
  assign t_plain = $time;
  assign t_sampled = $sampled($time);
  assign y = 64'(a) + $sampled($time);
  always_comb z = 64'(a) + $sampled($time);
  always_comb w = $sampled($time);

  initial begin
    #1;
    `checkd(w, 0);
    #6 a = 1;
    #10;
    `checkd(t_plain, 0);
    `checkd(t_sampled, 0);
    `checkd(y, 8);
    `checkd(z, 8);
    `checkd(w, 0);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
