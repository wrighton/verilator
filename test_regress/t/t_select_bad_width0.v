// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2024 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;

  parameter int ZERO = 0;

  initial begin
    automatic bit [31:0] val = '1;
    automatic int left = 4;
    automatic bit [1:0][255:0] lanes = '0;

    automatic int part = val[left+:ZERO];
    $display(part);
    part = val[left-:ZERO];
    $display(part);
    // A part-select too wide for an integer
    part = lanes[(1<<24)-1:0];
    $display(part);

    $write("*-* All Finished *-*\n");
    $finish;
  end

endmodule
