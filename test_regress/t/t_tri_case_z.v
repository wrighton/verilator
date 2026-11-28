// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// In a case statement, z in the expression matches only z in an item, and in casez or casex
// any bit (IEEE 1800-2023 12.5)

module drv (
    output wire [3:0] o,
    input logic oe,
    input logic [3:0] d
);
  assign o = oe ? d : 4'bzzzz;
endmodule

module pull_o (
    output wire [3:0] o
);
  pullup pu0 (o[0]);
  pulldown pd1 (o[1]);
  pullup pu2 (o[2]);
  pulldown pd3 (o[3]);
endmodule

module pull_mid (
    output wire [3:0] o
);
  pull_o u_pull (.o(o));
endmodule

module t;
  logic [3:0] vz;  // Procedurally high impedance
  logic [3:0] vp;  // Never high impedance
  logic [3:0] item;
  logic oe;
  wire [3:0] w;  // Driven by an enable
  wire [3:0] cw;  // Cell output
  tri1 [1:0] pu;  // Pulled up, not driven
  logic [69:0] wide;
  logic signed [1:0] ss;  // Procedurally high impedance, signed
  wire signed [1:0] ws;  // Driven by an enable, signed
  wire [3:0] cp, cpg, cpm, cpc;  // Pulled by cells, so not high impedance
  int r_vz, r_ord, r_nz, r_sel, r_ext, r_vp, r_w, r_cw, r_pu, r_wide, r_ss, r_ws, r_cp, r_cpg, r_cpm,
      r_cpc, r_z, r_zx, r_zv, r_x;

  assign w = oe ? 4'b0101 : 4'bzzzz;
  assign ws = oe ? 2'sb01 : 2'sbzz;
  drv u_drv (
      .o(cw),
      .oe(oe),
      .d(4'b1001)
  );
  pull_o u_cp (.o(cp));
  if (1) begin : gen
    pull_o u_cpg (.o(cpg));
  end
  pull_mid u_cpm (.o(cpm));
  pull_o u_cpc (.o({cpc[1:0], cpc[3:2]}));

  // verilog_format: off
`define CASES \
    case (vz) \
      4'bzzzz: r_vz = 1; \
      4'b0000: r_vz = 2; \
      4'bx0z0: r_vz = 3; \
      item: r_vz = 4; \
      4'b1z0z, 4'b0z0z: r_vz = 5; \
      default: r_vz = 6; \
    endcase \
    case (vz) \
      4'b0000: r_ord = 1; \
      4'bzzzz: r_ord = 2; \
      default: r_ord = 3; \
    endcase \
    case (vz) \
      4'b1x00: r_nz = 1; \
      4'b0000: r_nz = 2; \
      default: r_nz = 3; \
    endcase \
    case (vz[3:2]) \
      2'b0z: r_sel = 1; \
      2'b01: r_sel = 2; \
      default: r_sel = 3; \
    endcase \
    case (3'(vz[1:0])) \
      3'b0zz: r_ext = 1; \
      3'b000: r_ext = 2; \
      default: r_ext = 3; \
    endcase \
    case (vp) \
      4'bzzzz: r_vp = 1; \
      4'b0000: r_vp = 2; \
      default: r_vp = 3; \
    endcase \
    case (w) \
      4'b0101: r_w = 2; \
      4'bzzzz: r_w = 1; \
      default: r_w = 3; \
    endcase \
    case (cw) \
      4'bzzzz: r_cw = 1; \
      4'b1001: r_cw = 2; \
      default: r_cw = 3; \
    endcase \
    case (pu) \
      2'bzz: r_pu = 1; \
      2'b11: r_pu = 2; \
      default: r_pu = 3; \
    endcase \
    case (wide) \
      {2'bzz, 68'h0}: r_wide = 1; \
      70'h0: r_wide = 2; \
      default: r_wide = 3; \
    endcase \
    case (4'(ss)) \
      4'sbzzzz: r_ss = 1; \
      4'sb0000: r_ss = 2; \
      4'sb111z: r_ss = 3; \
      default: r_ss = 4; \
    endcase \
    case (cp) \
      4'b0101: r_cp = 1; \
      4'bzzzz: r_cp = 2; \
      default: r_cp = 3; \
    endcase \
    case (cpg) \
      4'b0101: r_cpg = 1; \
      default: r_cpg = 2; \
    endcase \
    case (cpm) \
      4'b0101: r_cpm = 1; \
      default: r_cpm = 2; \
    endcase \
    case (cpc) \
      4'b0101: r_cpc = 1; \
      default: r_cpc = 2; \
    endcase \
    case (4'(ws)) \
      4'sbzzzz: r_ws = 1; \
      4'sb0000: r_ws = 2; \
      4'sb0001: r_ws = 3; \
      default: r_ws = 4; \
    endcase \
    casez (vz) \
      4'b1???: r_z = 1; \
      4'bx1??: r_z = 2; \
      4'b0?00: r_z = 3; \
      default: r_z = 4; \
    endcase \
    casez (vz) \
      4'b0x00: r_zx = 1; \
      default: r_zx = 2; \
    endcase \
    casez (vz) \
      item: r_zv = 1; \
      default: r_zv = 2; \
    endcase \
    casex (vz) \
      4'b1xz1: r_x = 1; \
      4'b0x00: r_x = 2; \
      default: r_x = 3; \
    endcase
  // verilog_format: on

  initial begin
    vz = 4'bzzzz;
    ss = 2'sbzz;
    vp = 4'b0000;
    item = 4'b0000;
    oe = 1'b0;
    wide = {2'bzz, 68'h0};
    #1;
    `CASES
    `checkd(r_cp, 1);
    `checkd(r_cpg, 1);
    `checkd(r_cpm, 1);
    `checkd(r_cpc, 1);
    `checkd(r_ss, 1);
    `checkd(r_ws, 1);
    `checkd(r_vz, 1);
    `checkd(r_ord, 2);
    `checkd(r_nz, 3);
    `checkd(r_sel, 3);
    `checkd(r_ext, 1);
    `checkd(r_vp, 2);
    `checkd(r_w, 1);
    `checkd(r_cw, 1);
    `checkd(r_pu, 2);
    `checkd(r_wide, 1);
    `checkd(r_z, 1);
    `checkd(r_zx, 1);
    `checkd(r_zv, 1);
    `checkd(r_x, 1);

    // z matches neither 0 nor an item with x, nor a variable item
    vz = 4'b0z0z;
    ss = 2'sb1z;
    oe = 1'b1;
    wide = 70'h0;
    #1;
    `CASES
    `checkd(r_ss, 3);
    `checkd(r_ws, 3);
    `checkd(r_vz, 5);
    `checkd(r_ord, 3);
    `checkd(r_nz, 3);
    `checkd(r_sel, 1);
    `checkd(r_ext, 3);
    `checkd(r_w, 2);
    `checkd(r_cw, 2);
    `checkd(r_wide, 2);
    `checkd(r_z, 3);
    `checkd(r_zx, 1);
    `checkd(r_zv, 1);
    `checkd(r_x, 2);

    vz = 4'b0000;
    ss = 2'sb00;
    #1;
    `CASES
    `checkd(r_ss, 2);
    `checkd(r_ws, 3);
    `checkd(r_vz, 2);
    `checkd(r_ord, 1);
    `checkd(r_nz, 2);
    `checkd(r_sel, 3);
    `checkd(r_ext, 2);
    `checkd(r_z, 3);
    `checkd(r_zx, 2);
    `checkd(r_zv, 1);
    `checkd(r_x, 2);

    vz = 4'b0100;
    ss = 2'sb0z;
    item = 4'b0100;
    #1;
    `CASES
    `checkd(r_ss, 4);
    `checkd(r_ws, 3);
    `checkd(r_vz, 4);
    `checkd(r_nz, 3);
    `checkd(r_sel, 2);
    `checkd(r_ext, 2);
    `checkd(r_z, 3);
    `checkd(r_zx, 2);
    `checkd(r_zv, 1);
    `checkd(r_x, 2);

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
