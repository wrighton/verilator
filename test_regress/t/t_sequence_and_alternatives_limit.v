// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

// A sequence 'and' whose operands have more alternatives than are tracked per attempt
// keeps the latch combiner (see t_sequence_and_alternatives).
// The checks pin its current counts.

module t (
    input clk
);
  localparam int END = 300;
  localparam int NPROP = 1;

  int cyc = 0;
  bit [63:0] crc = 64'h5aef_0c8d_d70a_4497;
  wire a = crc[0] | crc[3];
  wire b = crc[5] | crc[9];
  wire c = crc[13] | crc[17];
  int passes[NPROP];
  int fails[NPROP];
  // Known limit: 126 passes and 60 failures, where attempts pass 121 times and fail 180 times
  assert property (@(posedge clk) disable iff (cyc > END) (a [*1:5] ##1 c) and (b [*2]))
    ++passes[0];
  else ++fails[0];

  always @(posedge clk) begin
    cyc <= cyc + 1;
    crc <= {crc[62:0], crc[63] ^ crc[2] ^ crc[0]};
    if (cyc == END + 5) begin
      `checkd(passes[0], 126);
      `checkd(fails[0], 60);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
