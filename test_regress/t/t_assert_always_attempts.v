// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

// An attempt of a whole property 'always p' starts on every tick and fails on the first tick
// where an evaluation of p started on or after its start fails (IEEE 1800-2023 16.12.11), each
// failing attempt running the fail statements (16.14.1). Each check is the number of attempts
// that fail, for p a sequence 'or' of fixed-length sequences.
module t (
    input clk
);
  int cyc = 0;
  bit [63:0] crc = 64'h5aef_0c8d_d70a_4497;
  // Mostly true, so the attempts live long
  wire a = crc[0] | crc[3] | crc[7];
  wire b = crc[5] | crc[9] | crc[11];
  wire c = crc[13] | crc[17] | crc[19];
  wire d = crc[21] | crc[25] | crc[27];
  // False only on tick 1 and on tick 2
  wire da = cyc != 1;
  wire db = cyc != 2;
  localparam int END = 200;
  int fails[6];
  // 2 failures, as attempts fail: the evaluation started on tick 0 fails on tick 2, but the
  // attempts started on ticks 0 and 1 already failed on tick 1, and the later ones do not fail
  assert property (@(posedge clk) disable iff (cyc > END) always (da ##2 db))
  else ++fails[0];
  // 185 failures, as attempts fail
  assert property (@(posedge clk) disable iff (cyc > END) always (a ##2 b))
  else ++fails[1];
  // 186 failures, as attempts fail
  assert property (@(posedge clk) disable iff (cyc > END) always ((a ##1 b) or (c ##1 d)))
  else ++fails[2];
  // 186 failures, as attempts fail
  assert property (@(posedge clk) disable iff (cyc > END)
                   always ((a ##1 b ##1 c) or (b ##2 d)))
  else ++fails[3];
  // 165 failures, as attempts fail
  assert property (@(posedge clk) disable iff (cyc > END || cyc % 37 == 5) always (a ##1 b ##1 c))
  else ++fails[4];
  // Known limit: 48 failures, one per failure of the operand, where 182 attempts fail. An operand
  // of more than 32 ticks is not tracked per attempt.
  assert property (@(posedge clk) disable iff (cyc > END) always (a ##40 b))
  else ++fails[5];

  always @(posedge clk) begin
    cyc <= cyc + 1;
    crc <= {crc[62:0], crc[63] ^ crc[2] ^ crc[0]};
    if (cyc == END + 5) begin
      `checkd(fails[0], 2);
      `checkd(fails[1], 185);
      `checkd(fails[2], 186);
      `checkd(fails[3], 186);
      `checkd(fails[4], 165);
      `checkd(fails[5], 48);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
