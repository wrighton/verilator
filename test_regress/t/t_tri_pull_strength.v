// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module sub (
    inout wire x
);
  pullup (weak1) (x);
endmodule

module t;
  reg en = 0;

  // Weak pulls overridden by strong drivers
  wire scl;
  wire sda;
  pullup (weak1) pu_scl (scl);
  pulldown (weak0) (sda);
  bufif1 (scl, 1'b0, en);
  bufif1 (sda, 1'b1, en);

  // Strength of the other value is ignored (IEEE 1800-2023 28.10)
  wire [6:0] up;
  wire [6:0] down;
  pullup (strong0, pull1) (up);
  pulldown (supply1, weak0) (down);
  pullup (weak1, supply0) (up);
  pulldown (pull0, strong1) (down);
  assign up = en ? 7'h12 : 7'hzz;
  assign down = en ? 7'h12 : 7'hzz;

  // Explicit default strength
  wire p1;
  wire p0;
  pullup (pull1) (p1);
  pulldown (pull0) (p0);
  bufif1 (p1, 1'b0, en);
  bufif1 (p0, 1'b1, en);

  // Pull in a submodule on an inout port
  wire io;
  sub u_sub (io);
  bufif1 (io, 1'b0, en);

  initial begin
    repeat (2) begin
      en = 0;
      #1;
      `checkh(scl, 1'b1);
      `checkh(sda, 1'b0);
      `checkh(up, 7'h7f);
      `checkh(down, 7'h0);
      `checkh(p1, 1'b1);
      `checkh(p0, 1'b0);
      `checkh(io, 1'b1);
      en = 1;
      #1;
      `checkh(scl, 1'b0);
      `checkh(sda, 1'b1);
      `checkh(up, 7'h12);
      `checkh(down, 7'h12);
      `checkh(p1, 1'b0);
      `checkh(p0, 1'b1);
      `checkh(io, 1'b0);
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
