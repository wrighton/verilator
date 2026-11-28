// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// The default fail statements of an assertion of a whole property 'always p' with no else clause
// run once for each failing attempt (IEEE 1800-2023 16.14.1), as the driver counts
module t (
    input clk
);
  int cyc = 0;
  bit [63:0] crc = 64'h5aef_0c8d_d70a_4497;
  wire a = crc[0] | crc[3] | crc[7];
  wire b = crc[5] | crc[9] | crc[11];
  localparam int END = 40;
  assert property (@(posedge clk) disable iff (cyc > END) always a);
  assert property (@(posedge clk) disable iff (cyc > END) always (b ##2 a));

  always @(posedge clk) begin
    $display("V %0d %0d %0d", cyc, a, b);
    cyc <= cyc + 1;
    crc <= {crc[62:0], crc[63] ^ crc[2] ^ crc[0]};
    if (cyc == END + 5) begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
