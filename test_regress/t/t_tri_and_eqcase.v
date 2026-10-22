// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2022 Antmicro Ltd
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv, expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0x exp=%0x (%s !== %s)\n", `__FILE__, `__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

module t (
    input clk
);

  int cyc = 0;
  wire [6:0] a = cyc[6:0];
  wire s = cyc[0];

  // Operators on non-tristate signals never produce z
  wire and_z = 1'bz === (a[0] & a[1]);
  wire redxor_z = (^a === 1'bz);
  wire redand_nz = (&a !== 1'bz);
  wire not_z = (~a === 7'bz);
  wire add_z = ((a + 7'd1) === 7'b000000z);
  wire concat_z = ({a, a} === 14'bz);
  wire cond_z = ((s ? a : 7'd0) === 7'bz);
  wire var_z = ({cyc[1:0], cyc[1:0]} === 4'bz);

  always @(posedge clk) begin
    cyc <= cyc + 1;
    `checkh(and_z, 1'b0);
    `checkh(redxor_z, 1'b0);
    `checkh(redand_nz, 1'b1);
    `checkh(not_z, 1'b0);
    `checkh(add_z, 1'b0);
    `checkh(concat_z, 1'b0);
    `checkh(cond_z, 1'b0);
    `checkh(var_z, 1'b0);
    `checkh((a[2:0] | 3'd1) === 3'bzz1, 1'b0);
    if (cyc == 9) begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
