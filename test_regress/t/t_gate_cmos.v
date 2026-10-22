// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module t;
  reg d = 0;
  reg n = 0;
  reg p = 0;

  // Transmission gate
  wire w;
  cmos tg (w, d, n, p);

  // Off state observed through pulls; also an instance list with a delay
  wire up;
  wire down;
  cmos #1 (up, d, n, p), (down, d, n, p);
  pullup (up);
  pulldown (down);

  // Array of instances
  reg [6:0] da = 0;
  reg [6:0] na = 0;
  reg [6:0] pa = 0;
  wire [6:0] wa;
  cmos tga[6:0] (wa, da, na, pa);
  pullup (wa);

  initial begin
    for (int i = 0; i < 16; ++i) begin
      da = 7'(i * 37 + 5);
      na = 7'(i * 91 + 3);
      pa = 7'(i * 53 + 11);
      #2;
      `checkh(wa, (da & (na | ~pa)) | ~(na | ~pa));
    end
    for (int i = 0; i < 16; ++i) begin
      d = i[0];
      n = i[1];
      p = i[2];
      #2;
      if (n || !p) begin
        `checkh(w, d);
        `checkh(up, d);
        `checkh(down, d);
      end else begin
        `checkh(w, 1'bz);
        `checkh(up, 1'b1);
        `checkh(down, 1'b0);
      end
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
