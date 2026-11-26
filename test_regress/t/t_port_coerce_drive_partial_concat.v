// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// A written input port reached through a concatenation drives only the bits of its net its
// driver reaches, where another driver writes other bits of the net

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);

// verilog_format: on

interface drv_if (
    input logic clk,
    input logic [44:0] v
);
  // verilator lint_off ASSIGNIN
  clocking cb @(posedge clk);
    output v;
  endclocking
  // verilator lint_on ASSIGNIN
endinterface

module dut (
    input logic clk,
    input logic [34:0] a,
    input logic [1:0] b,
    input logic [10:0] tl,
    output logic [44:0] seen,
    output logic [1:0] low
);
  always_ff @(posedge clk) begin
    seen <= {a, b, tl[9:2]};
    low <= tl[1:0];
  end
endmodule

// A 35, a 2 and an 8 bit part, the last a slice of a port whose net has a driver of other bits
module drv;
  drv_if d (
      .clk(dut.clk),
      .v  ({dut.a, {dut.b, dut.tl[9:2]}})
  );
  initial begin
    @(posedge dut.clk);
    d.cb.v <= 45'h0145726ab499;
    @(posedge dut.clk);
    d.cb.v <= 45'h00a39d706fa6;
  end
endmodule

bind dut drv u_drv ();

module t;
  logic clk = 0;
  always #5 clk = ~clk;
  wire [34:0] wa;
  wire [1:0] wb;
  wire [10:0] tail;
  logic [44:0] seen;
  logic [1:0] low;
  assign wa = 'z;
  assign wb = 'z;
  assign tail[1:0] = 2'b11;
  assign tail[10:2] = 9'bz;
  dut u (
      .clk(clk),
      .a(wa),
      .b(wb),
      .tl(tail),
      .seen(seen),
      .low(low)
  );
  initial begin
    repeat (2) @(posedge clk);
    #1;
    `checkh(seen, 45'h0145726ab499);
    @(posedge clk);
    #1;
    `checkh(seen, 45'h00a39d706fa6);
    `checkh(low, 2'b11);
    `checkh(tail[9:2], 8'ha6);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
