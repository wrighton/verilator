// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module t (
    input clk
);

  int cyc = 0;
  int idx = 3;
  // Sampled in ranges: elements 2 and 3, adjacent, with a part of 3, element 5, and part of 6
  logic [7:0][99:0] arr;
  // Sampled whole: too many ranges, a variable select, not wider than a quad
  logic [39:0][7:0] many;
  logic [7:0][99:0] dyn;
  logic [7:0][7:0] narrow;

  initial void'($value$plusargs("idx=%d", idx));

  // Each written before the reads, so only their sampled values are from the previous edge
  always @(posedge clk) begin
    cyc <= cyc + 1;
    for (int k = 0; k < 8; k++) begin
      arr[k] = 100'(cyc * 8 + k);
      dyn[k] = 100'(cyc * 8 + k);
      narrow[k] = 8'(cyc * 8 + k);
    end
    for (int k = 0; k < 40; k++) many[k] = 8'(cyc + k);
    if (cyc > 0) begin
      `checkh($sampled(arr[2]), 100'((cyc - 1) * 8 + 2));
      `checkh($sampled(arr[3]), 100'((cyc - 1) * 8 + 3));
      `checkh($sampled(arr[3][20:5]), 16'(100'((cyc - 1) * 8 + 3) >> 5));
      `checkh($sampled(arr[6][10:3]), 8'(100'((cyc - 1) * 8 + 6) >> 3));
      for (int k = 0; k <= 32; k += 2) `checkh($sampled(many[k]), 8'(cyc - 1 + k));
      `checkh($sampled(dyn[1]), 100'((cyc - 1) * 8 + 1));
      `checkh($sampled(dyn[idx]), 100'((cyc - 1) * 8 + idx));
      `checkh($sampled(narrow[4]), 8'((cyc - 1) * 8 + 4));
    end
    if (cyc == 10) begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end

  assert property (@(posedge clk) cyc == 0 || arr[5] == 100'((cyc - 1) * 8 + 5));
endmodule
