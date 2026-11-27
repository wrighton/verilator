// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Michael Wrighton
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module t;
  // A stream narrower than a fixed-size unpacked array is left-aligned in it, and filled with
  // zero bits on the right (IEEE 1800-2023 11.4.14)
  initial begin
    automatic logic [11:0] s12 = 12'habc;
    automatic logic [31:0] s32 = 32'h1234_5678;
    automatic logic [63:0] s64 = 64'h1234_5678_9abc_def0;
    automatic logic [69:0] s70 = {6'h3f, s64};
    automatic logic [7:0] b2[2];
    automatic logic [7:0] b22[2][2];
    automatic logic [32:0] q1[1];
    automatic logic [64:0] w1[1];
    automatic logic [64:0] w2[2];
    automatic logic [31:0] i3[3];
    b2 = {>>{s12}};
    `checkh(b2[0], 8'hab);
    `checkh(b2[1], 8'hc0);
    b22 = {>>{s12}};
    `checkh(b22[0][0], 8'hab);
    `checkh(b22[0][1], 8'hc0);
    `checkh(b22[1][0], 8'h00);
    `checkh(b22[1][1], 8'h00);
    q1 = {>>{s32}};
    `checkh(q1[0], {s32, 1'b0});
    w1 = {>>{s64}};
    `checkh(w1[0], {s64, 1'b0});
    w2 = {>>{s32}};
    `checkh(w2[0], {s32, 33'h0});
    `checkh(w2[1], 65'h0);
    // An unpack that needs more bits than the source provides is an error
    // (IEEE 1800-2023 11.4.14.3), and also takes zero bits
    // verilator lint_off WIDTHEXPAND
    {>>{i3}} = s70;
    // verilator lint_on WIDTHEXPAND
    `checkh(i3[0], s70[69:38]);
    `checkh(i3[1], s70[37:6]);
    `checkh(i3[2], {s70[5:0], 26'h0});
    // Each dimension in its declared order, whatever its direction
    begin
      automatic logic [27:0] s28 = 28'h1234567;
      automatic logic [9:0] s10 = 10'h3aa;
      automatic logic [6:0] a[2:3][6:5];
      automatic logic [6:0] b[3:2][5:6];
      automatic logic [27:0] p;
      a = {>>{s28}};
      `checkh(a[2][6], 7'h09);
      `checkh(a[2][5], 7'h0d);
      `checkh(a[3][6], 7'h0a);
      `checkh(a[3][5], 7'h67);
      p = {>>{a}};
      `checkh(p, s28);
      b = {>>{s28}};
      `checkh(b[3][5], 7'h09);
      `checkh(b[3][6], 7'h0d);
      `checkh(b[2][5], 7'h0a);
      `checkh(b[2][6], 7'h67);
      p = {>>{b}};
      `checkh(p, s28);
      a = {>>{s10}};
      `checkh(a[2][6], 7'h75);
      `checkh(a[2][5], 7'h20);
      `checkh(a[3][6], 7'h00);
      `checkh(a[3][5], 7'h00);
    end
    // Also a descending dimension past the 32nd
    begin
      automatic bit deep[0:0][0:0][0:0][0:0][0:0][0:0][0:0][0:0][0:0][0:0][0:0][0:0][0:0][0:0][0:0][0:0][0:0][0:0][0:0][0:0][0:0][0:0][0:0][0:0][0:0][0:0][0:0][0:0][0:0][0:0][0:0][0:0][1:0];
      automatic bit [1:0] p2;
      deep = {>>{2'b10}};
      `checkh(deep[0][0][0][0][0][0][0][0][0][0][0][0][0][0][0][0][0][0][0][0][0][0][0][0][0][0][0][0][0][0][0][0][1], 1'b1);
      `checkh(deep[0][0][0][0][0][0][0][0][0][0][0][0][0][0][0][0][0][0][0][0][0][0][0][0][0][0][0][0][0][0][0][0][0], 1'b0);
      p2 = {>>{deep}};
      `checkh(p2, 2'b10);
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
