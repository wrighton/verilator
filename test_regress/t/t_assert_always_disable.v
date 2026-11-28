// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

// A disable condition holding between two ticks disables the pending attempts of a whole property
// 'always p' (IEEE 1800-2023 16.12), whose later failures are not reported. Each check is the
// number of attempts that fail.
module t;
  logic clk = 0;
  int cyc = 0;
  bit [63:0] crc = 64'h5aef_0c8d_d70a_4497;
  wire a = crc[0] | crc[3] | crc[7];
  wire b = crc[5] | crc[9] | crc[11];
  wire c = crc[13] | crc[17] | crc[19];
  wire d = crc[21] | crc[25] | crc[27];
  localparam int END = 120;
  logic dis = 0;
  logic quiet = 0;  // A term of the disable condition that never holds
  int fails[2];
  // 68 failures, as attempts fail
  assert property (@(posedge clk) disable iff (dis) always a)
  else ++fails[0];
  // The same, with a sampled value in the disable condition
  assert property (@(posedge clk) disable iff (dis || $sampled(quiet)) always a)
  else ++fails[1];

  always @(posedge clk) begin
    cyc <= cyc + 1;
    crc <= {crc[62:0], crc[63] ^ crc[2] ^ crc[0]};
  end

  initial begin
    repeat (END) begin
      #5 clk = 1;
      #2;
      // A pulse wholly between this tick and the next
      if (cyc % 13 == 7) begin
        dis = 1;
        #1 dis = 0;
      end else begin
        #1;
      end
      #2 clk = 0;
    end
    #5 clk = 1;
    #5;
    `checkd(fails[0], 68);
    `checkd(fails[1], 68);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
