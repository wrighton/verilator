// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2014 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module sub #(
    parameter int MAX = $
) (
    input int cyc,
    output bit in_range
);
  assign in_range = cyc inside {[3 : MAX]};
endmodule

module t (
    input clk
);

  parameter int UNB  /*verilator public_flat_rw*/ = $;
  localparam int UNB2 = $;
  localparam int UNB3 = UNB;
  localparam SIX = 6;

  initial begin
    if ($bits($isunbounded(0)) !== 1) $stop;
    if ($isunbounded(0) !== 1'b0) $stop;
    if ($isunbounded(SIX) !== 0) $stop;
    if ($isunbounded($) !== 1) $stop;
    if ($isunbounded(UNB) !== 1) $stop;
    if ($isunbounded(UNB2) !== 1) $stop;
    if ($isunbounded(UNB3) !== 1) $stop;
  end

  initial begin
    int q[$:UNB2];
    q.push_back(1);
    q.push_back(2);
    if (q.size() != 2) $stop;
  end

  // A parameter of '$' may be used where a literal '$' may (IEEE 1800-2023 6.20.2.1)
  int cyc = 0;

  assert property (@(posedge clk) cyc == 3 |-> ##[1:UNB] cyc == 15) else $stop;
  assert property (@(posedge clk) cyc == 3 |-> cyc > 2 [*1:UNB3] ##1 cyc == 15) else $stop;

  always @(posedge clk) if ((cyc inside {[5 : UNB2]}) != (cyc >= 5)) $stop;

  bit in_unb;
  bit in_max;
  sub u_unb (.cyc, .in_range(in_unb));
  sub #(.MAX(7)) u_max (.cyc, .in_range(in_max));
  always @(negedge clk) begin
    if (in_unb != (cyc >= 3)) $stop;
    if (in_max != (cyc >= 3 && cyc <= 7)) $stop;
  end

  always @(posedge clk) begin
    cyc <= cyc + 1;
    if (cyc == 20) begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
