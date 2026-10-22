// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv, expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0x exp=%0x (%s !== %s)\n", `__FILE__, `__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

// Compares its input port with z; the port has no tristate driver in this module
module sub (
    input [2:0] in,
    output isz,
    output is0z
);
  assign isz = in === 3'bzzz;
  assign is0z = in[0] !== 1'bz;
endmodule

module t (
    input clk
);

  int cyc = 0;
  wire [2:0] v = cyc[2:0];
  wire en = cyc[1];
  wire [2:0] w;
  assign w = en ? v : 3'bz;

  wire var_z, var_0z;
  sub u_var (.in(v), .isz(var_z), .is0z(var_0z));
  wire tri_z, tri_0z;
  sub u_tri (.in(w), .isz(tri_z), .is0z(tri_0z));
  wire expr_z, expr_0z;
  sub u_expr (.in(v + 3'd1), .isz(expr_z), .is0z(expr_0z));

  always @(posedge clk) begin
    cyc <= cyc + 1;
    `checkh(var_z, 1'b0);
    `checkh(var_0z, 1'b1);
    `checkh(tri_z, !en);
    `checkh(tri_0z, en);
    `checkh(expr_z, 1'b0);
    `checkh(expr_0z, 1'b1);
    if (cyc == 9) begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
