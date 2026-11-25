// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module t;
  import "DPI-C" context function void call_bump();
  export "DPI-C" function bump;

  int acc[8];

  // An exported function without arguments, larger than the split limit
  function void bump();
    if (acc[0] >= 0) begin
      acc[0] = acc[0] * 3 + 0;
      acc[1] = acc[5] * 3 + 1;
      acc[2] = acc[2] * 3 + 2;
      acc[3] = acc[7] * 3 + 3;
      acc[4] = acc[4] * 3 + 4;
      acc[5] = acc[1] * 3 + 5;
      acc[6] = acc[6] * 3 + 6;
      acc[7] = acc[3] * 3 + 7;
      acc[0] = acc[0] * 3 + 8;
      acc[1] = acc[5] * 3 + 9;
      acc[2] = acc[2] * 3 + 10;
      acc[3] = acc[7] * 3 + 11;
      acc[4] = acc[4] * 3 + 12;
      acc[5] = acc[1] * 3 + 13;
      acc[6] = acc[6] * 3 + 14;
      acc[7] = acc[3] * 3 + 15;
      acc[0] = acc[0] * 3 + 16;
      acc[1] = acc[5] * 3 + 17;
      acc[2] = acc[2] * 3 + 18;
      acc[3] = acc[7] * 3 + 19;
      acc[4] = acc[4] * 3 + 20;
      acc[5] = acc[1] * 3 + 21;
      acc[6] = acc[6] * 3 + 22;
      acc[7] = acc[3] * 3 + 23;
    end
  endfunction

  initial begin
    call_bump();
    `checkd(acc[0], 40);
    `checkd(acc[1], 353);
    `checkd(acc[2], 66);
    `checkd(acc[3], 595);
    `checkd(acc[4], 92);
    `checkd(acc[5], 1080);
    `checkd(acc[6], 118);
    `checkd(acc[7], 1808);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
