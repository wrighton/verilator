// DESCRIPTION: Verilator: Display scope of concurrent assertion actions
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// An action keeps the scope of its assertion for %m, also when run in the Reactive region: the
// same as before, with the assertion's block named internally.
// p until q fails at tick 3 for the attempts of ticks 0-3 and at ticks 7 and 8 for those of
// these ticks; p2 until q2 at tick 5 for those of ticks 0-5 (IEEE 1800-2023 16.12.12).
module t;
  localparam int T = 9;
  localparam bit P[T] = '{1, 1, 1, 0, 0, 0, 0, 0, 0};
  localparam bit Q[T] = '{0, 0, 0, 0, 1, 1, 1, 0, 0};
  localparam bit P2[T] = '{1, 1, 1, 1, 1, 0, 1, 1, 1};
  localparam bit Q2[T] = '{0, 0, 0, 0, 0, 0, 1, 0, 0};

  bit clk = 0;
  int cyc = 0;
  bit p = P[0];
  bit q = Q[0];
  bit p2 = P2[0];
  bit q2 = Q2[0];

  lbl_top :
  assert property (@(posedge clk) p until q)
  else $display("[%0t] %m", $time);

  if (1) begin : gen
    lbl_gen :
    assert property (@(posedge clk) p2 until q2)
    else $display("[%0t] %m", $time);
  end

  always #5 clk = ~clk;
  always @(posedge clk) cyc <= cyc + 1;

  always @(negedge clk) begin
    if (cyc < T) begin
      p = P[cyc];
      q = Q[cyc];
      p2 = P2[cyc];
      q2 = Q2[cyc];
    end
    else begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
