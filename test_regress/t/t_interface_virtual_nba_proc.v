// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0)
// verilog_format: on

interface ifc;
  logic [6:0] q = 0;
  logic [14:0] w = 0;
  logic [30:0] resp = 0;
  logic [8:0] x = 0;

  function automatic logic [6:0] peek();
    // verilator no_inline_task
    return q;
  endfunction
  function automatic logic [8:0] peek_x();
    // verilator no_inline_task
    return x;
  endfunction
endinterface

module t (
    input clk
);
  int cyc = 0;
  logic [63:0] crc = 64'h5aef0c8d_d70a4497;
  always @(posedge clk) begin
    cyc <= cyc + 1;
    crc <= {crc[62:0], crc[63] ^ crc[2] ^ crc[0]};
    if (cyc == 99) begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end

  // A read through a virtual interface on the edge of a nonblocking assignment
  // to the member, in another process, sees the value before the assignment
  // (IEEE 1800-2023 4.9.4). Both processes also do unrelated work. The reader
  // reads two members, directly and in a method.
  ifc i ();
  virtual ifc vi = i;
  logic [63:0] wa = 0;
  always @(posedge clk) begin
    i.w <= crc[14:0];
    i.x <= crc[23:15];
    for (int k = 0; k < 64; ++k) wa[k] <= ^(crc & (64'h1 << k)) ^ wa[(k+7)%64];
  end
  logic [14:0] w_exp = 0;
  logic [8:0] x_exp = 0;
  logic [63:0] ra = 0;
  always @(posedge clk) begin
    for (int k = 0; k < 64; ++k) ra[k] <= ^(crc & (64'h3 << k)) ^ ra[(k+5)%64];
    w_exp <= crc[14:0];
    x_exp <= crc[23:15];
    if (cyc > 1) begin
      `checkh(vi.w, w_exp);
      `checkh(vi.peek_x(), x_exp);
    end
    if (cyc == 98 && wa == ra) `stop;
  end
endmodule
