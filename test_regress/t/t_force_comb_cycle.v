// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0)
// verilog_format: on

// A net forced from a net that mirrors it forms a combinational cycle
module mirror #(
    parameter int WIDTH = 1
) (
    input logic en,
    input logic [WIDTH-1:0] drv
);
  // verilator lint_off UNOPTFLAT
  wire [WIDTH-1:0] pin;
  wire [WIDTH-1:0] mon;
  // verilator lint_on UNOPTFLAT
  assign mon = en ? drv : pin;
  initial force pin = mon;
endmodule

module t;
  logic en = 1'b1;
  logic [64:0] drv;

  mirror #(.WIDTH(7)) narrow (
      en,
      drv[6:0]
  );
  mirror #(.WIDTH(65)) wide (
      en,
      drv
  );

  initial begin
    for (int cycle = 0; cycle < 6; ++cycle) begin
      // While mirroring, the forced net holds its last value
      if (cycle == 4) en = 1'b0;
      drv = 65'h1_1234_5678_9abc_def0 ^ 65'(cycle * 13);
      #1;
      `checkh(narrow.pin, 7'(65'h1_1234_5678_9abc_def0 ^ 65'((cycle < 4 ? cycle : 3) * 13)));
      `checkh(wide.pin, 65'h1_1234_5678_9abc_def0 ^ 65'((cycle < 4 ? cycle : 3) * 13));
      `checkh(narrow.mon, narrow.pin);
      `checkh(wide.mon, wide.pin);
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
