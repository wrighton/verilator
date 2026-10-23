// DESCRIPTION: Verilator: Verilog Test module
//
// This program is free software; you can redistribute it and/or modify it
// under the terms of either the GNU Lesser General Public License Version 3
// or the Perl Artistic License Version 2.0.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: LGPL-3.0-only OR Artistic-2.0

// Ref. to IEEE 1800-2023 11.4.14
//
// Streaming an unpacked array whose element is an unpacked struct.  The left
// stream ({<<{}}) read used to crash V3EmitC: V3Const packed the aggregate
// source but then re-wrapped the now-packed expression in AstCvtArrayToPacked,
// which EmitC dereferenced as an array.

module t (
    input clk
);

  `define checkh(gotv, expv) \
    do if ((gotv) !== (expv)) begin \
      $write("%%Error: %s:%0d: got='h%x exp='h%x\n", `__FILE__, `__LINE__, (gotv), (expv)); \
      $stop; \
    end while (0);

  typedef struct {
    logic [7:0] a;
    logic [7:0] b;
  } s_t;
  typedef s_t arr_t[2];  // unpacked array of unpacked struct

  localparam int W = $bits(arr_t);

  integer cyc = 0;
  reg [63:0] crc = 64'h5aef0c8d_d70a4497;
  wire [W-1:0] src = crc[W-1:0];

  arr_t aw_r, aw_l;
  always_comb{>>{aw_r}} = src;
  always_comb{<<8{aw_l}} = src;

  wire [W-1:0] rd_r = {>>{aw_r}};
  wire [W-1:0] rd_l = {<<8{aw_l}};  // {<<{}} read of aggregate array previously crashed

  // Streaming is by left-to-right element order, also with nonzero bounds
  typedef s_t dsc_t[3:1];
  typedef s_t asc_t[1:3];
  wire [47:0] src3 = crc[47:0];
  dsc_t dw;
  asc_t awa;
  always_comb{>>{dw}} = src3;
  always_comb{>>{awa}} = src3;
  wire [47:0] rd_d = {>>{dw}};
  wire [47:0] rd_a = {>>{awa}};

  always @(posedge clk) begin
    cyc <= cyc + 1;
    crc <= {crc[62:0], crc[63] ^ crc[2] ^ crc[0]};
    if (cyc > 1) begin
      `checkh(rd_r, src);
      `checkh(rd_l, src);
      `checkh(dw[3].a, src3[47:40]);
      `checkh(dw[2].b, src3[23:16]);
      `checkh(dw[1].b, src3[7:0]);
      `checkh(awa[1].a, src3[47:40]);
      `checkh(awa[3].b, src3[7:0]);
      `checkh(rd_d, src3);
      `checkh(rd_a, src3);
    end
    if (cyc == 20) begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end

endmodule
