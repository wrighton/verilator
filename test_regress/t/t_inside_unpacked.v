// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2020 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t (
    input clk
);

  integer cyc = 0;

  int array[10];
  logic l;

  always @(posedge clk) begin
    cyc <= cyc + 1;
    if (cyc == 0) begin
      // Setup
      array[0] = 10;
      array[1] = 20;
      array[9] = 90;
    end
    else if (cyc < 99) begin
      l = (10 inside {array});
      if (l != 1) $stop;
      l = (20 inside {array});
      if (l != 1) $stop;
      l = (90 inside {array});
      if (l != 1) $stop;
      l = (99 inside {array});
      if (l != 0) $stop;
    end
    else if (cyc == 99) begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end

  // A value wider than the elements is compared at its width, with the elements extended
  bit [2:0] narrow[2] = '{3'd1, 3'd2};
  logic signed [2:0] snarrow[2] = '{-3'sd1, 3'sd2};
  int q[$] = '{9, 32'hffff_ffff};
  bit [3:0] key4;
  logic signed [3:0] skey4;
  bit [39:0] key40;
  initial begin
    key4 = 4'd9;
    skey4 = -4'sd1;
    /* verilator lint_off WIDTHTRUNC */
    if (key4 inside {narrow}) $stop;
    key4 = 4'd2;
    if (!(key4 inside {narrow})) $stop;
    if (!(skey4 inside {snarrow})) $stop;
    key4 = 4'd15;
    if (key4 inside {snarrow}) $stop;
    key4 = 4'd7;
    if (!(key4 inside {snarrow})) $stop;
    key40 = 40'h1_0000_0009;
    if (key40 inside {q}) $stop;
    key40 = 40'h00_ffff_ffff;
    if (!(key40 inside {q})) $stop;
    /* verilator lint_on WIDTHTRUNC */
  end

endmodule
