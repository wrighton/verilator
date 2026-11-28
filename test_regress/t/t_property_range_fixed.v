// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// An attempt of a ranged delay of a multi-cycle sequence fails on the tick its last candidate
// fails (IEEE 1800-2023 16.7, 16.12.7), not the last tick a candidate could end, so a disable
// or the end of the simulation between them does not lose the failure
module t;
  localparam int NCYC = 60;
  logic clk = 0;
  always #5 clk = ~clk;
  int cyc = 0;
  bit [63:0] crc = 64'h5aef0c8d_d70a4497;
  wire b = cyc == 2;
  wire c = 1'b0;
  // Candidate 11 matches c and fails d on 12, candidate 12 fails c on 12
  wire a1 = cyc == 10;
  wire c1 = cyc == 11;
  wire d1 = 1'b0;
  wire rst = cyc == 23;
  wire b2 = cyc == 20;
  // The last candidate fails on tick 58, before the end of the simulation
  wire b3 = cyc == 56;
  wire e = crc[0];
  wire f = crc[1];
  bit he[NCYC];
  bit hf[NCYC];
  always @(posedge clk) begin
    he[cyc] = e;
    hf[cyc] = f;
  end

  int fails[6];
  int failTick[6];
  assert property (@(posedge clk) b |-> ##[0:2] (c ##1 c ##1 c))
  else begin
    ++fails[0];
    failTick[0] = $sampled(cyc);
  end
  assert property (@(posedge clk) a1 |-> ##[1:2] (c1 ##1 d1))
  else begin
    ++fails[1];
    failTick[1] = $sampled(cyc);
  end
  // Disabled after the last candidate failed, before the last end
  assert property (@(posedge clk) disable iff (rst) b2 |-> ##[0:2] (c ##1 c ##1 c))
  else ++fails[2];
  assert property (@(posedge clk) b3 |-> ##[0:2] (c ##1 c ##1 c ##1 c ##1 c))
  else begin
    ++fails[3];
    failTick[3] = $sampled(cyc);
  end
  // Overlapping attempts
  assert property (@(posedge clk) cyc < 40 |-> ##[1:2] (e ##1 f))
  else ++fails[4];
  // A sequence 'or' of operands of a fixed length
  assert property (@(posedge clk) cyc < 40 |-> ##[1:2] (##1 ((e ##1 f) or (f ##1 e))))
  else ++fails[5];

  function automatic int attemptFails(int k);
    int n = 0;
    for (int s = 0; s < 40; ++s) begin
      bit ok = 0;
      for (int d = 1; d <= 2; ++d) begin
        if (k == 4 && he[s+d] && hf[s+d+1]) ok = 1;
        if (k == 5 && ((he[s+d+1] && hf[s+d+2]) || (hf[s+d+1] && he[s+d+2]))) ok = 1;
      end
      if (!ok) ++n;
    end
    return n;
  endfunction

  always @(posedge clk) begin
    cyc <= cyc + 1;
    crc <= {crc[62:0], crc[63] ^ crc[2] ^ crc[0]};
    if (cyc == NCYC - 1) begin
      `checkd(fails[0], 1);
      `checkd(failTick[0], 4);
      `checkd(fails[1], 1);
      `checkd(failTick[1], 12);
      `checkd(fails[2], 1);
      `checkd(fails[3], 1);
      `checkd(failTick[3], 58);
      `checkd(fails[4], attemptFails(4));
      `checkd(fails[5], attemptFails(5));
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
