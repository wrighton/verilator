// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2020 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module t (
    input clk
);

  wire o_n;
  wire o_p;
  wire o_0;
  wire o_1;

  // verilator lint_off PINMISSING
  sub_0 sub_0 (.o_0);
  sub_1 sub_1 (.o_1);
  sub_n sub_n (.o_n);
  ifc_1 ifc_1 ();
  prg_1 prg_1 (.o_p);
  // verilator lint_on PINMISSING

  always @(posedge clk) begin
    if (o_0 !== 1'b0) $stop;
    if (o_1 !== 1'b1) $stop;
    //4-state if (o_n !== 1'bz) $stop;
    `checkh(ifc_1.o_i, 1'b1);
    `checkh(o_p, 1'b1);
    $write("*-* All Finished *-*\n");
    $finish;
  end

endmodule

`unconnected_drive pull0
module sub_0 (
    input i,
    output wire o_0
);
  assign o_0 = i;
endmodule

`unconnected_drive pull1
module sub_1 (
    input i,
    output wire o_1
);
  assign o_1 = i;
endmodule

`nounconnected_drive
module sub_n (
    input i,
    output wire o_n
);
  assign o_n = i;
endmodule

`unconnected_drive pull1
interface ifc_1 (
    input i
);
  wire o_i;
  assign o_i = i;
endinterface

program prg_1 (
    input i,
    output wire o_p
);
  assign o_p = i;
endprogram
`nounconnected_drive
