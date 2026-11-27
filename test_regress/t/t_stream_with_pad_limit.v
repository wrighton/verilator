// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Michael Wrighton
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkp(gotv,expv_s) do begin string gotv_s; gotv_s = $sformatf("%p", gotv); if ((gotv_s) != (expv_s)) begin $write("%%Error: %s:%0d:  got='%s' exp='%s'\n", `__FILE__,`__LINE__, (gotv_s), (expv_s)); `stop; end end while(0);
// verilog_format: on

module t;
  // A with[] range of more items than an int holds, as positions that do not fit in 32 bits
  // give, streams only the array, not about 2**32 padded items (IEEE 1800-2023 11.4.14.4)
  int q[$];
  int r[$];
  longint wide = 64'sh1_0000_0001;
  initial begin
    q = '{1, 2, 3, 4};
    // verilator lint_off WIDTHEXPAND
    r = {>>{q with [$-64'h1_0000_0001:$]}};
    `checkp(r, "'{'h1, 'h2, 'h3, 'h4}");
    r = {>>{q with [0:$-(-64'sh1_0000_0000)]}};
    `checkp(r, "'{'h1, 'h2, 'h3, 'h4}");
    // verilator lint_on WIDTHEXPAND
    r = {>>{q with [0:64'sh1_0000_0000]}};
    `checkp(r, "'{'h1, 'h2, 'h3, 'h4}");
    r = {>>{q with [0:wide]}};
    `checkp(r, "'{'h1, 'h2, 'h3, 'h4}");
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
