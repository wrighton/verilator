// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Michael Wrighton
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module t;
  // An unpack needing more bits than the source provides is an error (IEEE 1800-2023
  // 11.4.14.3), and takes zero bits for the rest
  initial begin
    automatic logic [69:0] s70 = 70'h3f_0123_4567_89ab_cdef;
    automatic logic [11:0] s12 = 12'habc;
    automatic logic [31:0] i3[3];
    automatic logic [7:0] c2[2];
    // verilator lint_off WIDTHEXPAND
    {>>{i3}} = s70;
    {<<8{c2}} = s12;
    // verilator lint_on WIDTHEXPAND
    `checkh(i3[0], s70[69:38]);
    `checkh(i3[1], s70[37:6]);
    `checkh(i3[2], {s70[5:0], 26'h0});
    `checkh(c2[0], 8'hbc);
    `checkh(c2[1], 8'ha0);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
