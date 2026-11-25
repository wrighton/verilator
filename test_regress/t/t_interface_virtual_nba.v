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

  function automatic logic [6:0] peek();
    // verilator no_inline_task
    return q;
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
  // to the member sees the value before the assignment (IEEE 1800-2023 4.9.4)
  ifc i1 ();
  virtual ifc v1 = i1;
  logic [6:0] exp1 = 0;
  always @(posedge clk) begin
    i1.q <= crc[6:0];
    exp1 <= crc[6:0];
    if (cyc > 1) begin
      `checkh(v1.q, exp1);
      `checkh(v1.peek(), exp1);
    end
  end

endmodule
