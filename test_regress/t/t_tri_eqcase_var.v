// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Case equality with z of variables that are never z, next to a tristate net

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

package pkg;
  logic pv;
endpackage

module t (
    input clk
);

  integer cyc = 0;
  reg [63:0] crc = 64'h5aef0c8d_d70a4497;

  logic [3:0] a;
  logic b;
  wire [1:0] w = crc[9:8];
  wire tri_net;
  wire [1:0] w_half;
  assign w_half[0] = crc[12];
  assign tri_net = crc[10] ? crc[11] : 1'bz;

  // verilator lint_off UNDRIVEN
  wire undriven;
  logic unset;
  // verilator lint_on UNDRIVEN

  always_comb begin
    a = crc[3:0];
    b = crc[4];
    pkg::pv = crc[5];
  end

  always @(posedge clk) begin
    cyc <= cyc + 1;
    crc <= {crc[62:0], crc[63] ^ crc[2] ^ crc[0]};
    `checkd(a[1] === 1'bz, 1'b0);
    `checkd(a[1] !== 1'bz, 1'b1);
    `checkd(a === 4'bzzzz, 1'b0);
    `checkd(b === 1'bz, 1'b0);
    `checkd(w === 2'bz0, 1'b0);
    `checkd(w[0] === 1'bz, 1'b0);
    `checkd(pkg::pv === 1'bz, 1'b0);
    `checkd(tri_net === 1'bz, !crc[10]);
    `checkd(undriven === 1'bz, 1'b1);
    `checkd(w_half[1] === 1'bz, 1'b1);
    `checkd(unset === 1'bz, 1'b0);
    if (cyc == 20) begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end

endmodule
