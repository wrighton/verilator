// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0x exp=%0x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module t;
  localparam logic [63:0] NEG_ZERO = 64'h8000_0000_0000_0000;

  real source = 1.0;
  real delivered;

  // A delayed continuous assignment of a real, which follows a change between 0.0 and -0.0
  assign #2 delivered = source;

  initial begin
    #5 source = 0.0;
    #5;
    `checkh($realtobits(delivered), 64'h0);
    source = $bitstoreal(NEG_ZERO);
    #5;
    `checkh($realtobits(delivered), NEG_ZERO);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
