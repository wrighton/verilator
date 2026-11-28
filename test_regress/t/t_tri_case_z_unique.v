// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// The checks of unique and priority compare z in the expression as the items do
// (IEEE 1800-2023 12.5.3)

module t;
  logic [3:0] vz;  // Procedurally high impedance
  int r_pri, r_uq, r_uqz;

  initial begin
    vz = 4'bzzzz;
    #1;
    priority case (vz)
      4'bzzzz: r_pri = 1;
      4'b0000: r_pri = 2;
    endcase
    unique case (vz)
      4'b0000: r_uq = 2;
      4'bzzzz: r_uq = 1;
    endcase
    `checkd(r_pri, 1);
    `checkd(r_uq, 1);

    vz = 4'b1zz0;
    #1;
    unique casez (vz)
      4'b1???: r_uqz = 1;
      4'b?1?1: r_uqz = 2;
      default: r_uqz = 3;
    endcase
    `checkd(r_uqz, 1);

    vz = 4'b0001;
    #1;
    unique casez (vz)
      4'b1???: r_uqz = 1;
      4'b?1?1: r_uqz = 2;
      default: r_uqz = 3;
    endcase
    `checkd(r_uqz, 3);

    // A bit with x matches only z
    vz = 4'b1zzz;
    #1;
    priority casez (vz)
      4'b1x??: r_pri = 3;
    endcase
    `checkd(r_pri, 3);
    // Both items match, so a violation
    unique casez (vz)
      4'b1x??: r_uqz = 1;
      4'b???1: r_uqz = 2;
    endcase
    `checkd(r_uqz, 1);

    // Neither item matches z in one bit
    vz = 4'b0z00;
    #1;
    unique case (vz)
      4'b0000: r_uq = 2;
      4'bzzzz: r_uq = 1;
    endcase
    // Allow for a deferred report of the violation
    #1;
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
