// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// A written input port drives the bits it connects of a net driven elsewhere

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

interface drv_if (
    input logic clk,
    input logic [7:0] v
);
  // verilator lint_off ASSIGNIN
  clocking cb @(posedge clk);
    output v;
  endclocking
  // verilator lint_on ASSIGNIN
endinterface

module dut (
    input logic clk,
    input logic [7:0] v,
    output logic [7:0] seen
);
  always_ff @(posedge clk) seen <= v;
endmodule

module drv;
  drv_if d (
      .clk(dut.clk),
      .v  (dut.v)
  );
  initial begin
    @(posedge dut.clk);
    d.cb.v <= 8'hA5;
  end
endmodule

bind dut drv u_drv ();

module t;
  logic clk = 0;
  always #5 clk = ~clk;
  wire [10:0] tail;
  logic [7:0] seen;
  // A driver only on the low two bits, which the connection does not select
  assign tail[1:0] = 2'b11;
  assign tail[10:2] = 9'bz;
  dut u (
      .clk(clk),
      .v(tail[9:2]),
      .seen(seen)
  );
  initial begin
    repeat (4) @(posedge clk);
    `checkh(seen, 8'hA5);
    `checkh(tail[1:0], 2'b11);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
