// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

`define STRINGIFY(x) `"x`"

// Values dumped by several threads every cycle

module t;
  logic clk = 0;
  always #5 clk = ~clk;

  logic [70:0] lfsr = 1;
  logic [6:0] up = 0;
  logic [14:0] down = 0;
  int cyc = 0;
  always_ff @(posedge clk) begin
    lfsr <= {lfsr[69:0], lfsr[70] ^ lfsr[5]};
    up <= up + 7'd1;
    down <= down - 15'd3;
    cyc <= cyc + 1;
    if (cyc == 2000) begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end

  initial begin
    $dumpfile(`STRINGIFY(`TEST_DUMPFILE));
    $dumpvars();
  end
endmodule
