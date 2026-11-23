// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0x exp=%0x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

interface bus_if;
  real value = 0.0;
endinterface

module t;
  localparam logic [63:0] NAN = 64'h7ff8_0000_0000_0000;
  localparam logic [63:0] NEG_ZERO = 64'h8000_0000_0000_0000;

  bus_if bus ();
  virtual bus_if vif = bus;
  logic [63:0] observed;

  // Logic reading a real member written through a virtual interface, which settles when the
  // member keeps a NaN, and follows a change between 0.0 and -0.0
  always_comb observed = $realtobits(vif.value);

  initial begin
    #1 vif.value = $bitstoreal(NAN);
    #1;
    `checkh(observed, NAN);
    vif.value = 0.0;
    #1;
    `checkh(observed, 64'h0);
    vif.value = $bitstoreal(NEG_ZERO);
    #1;
    `checkh(observed, NEG_ZERO);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
