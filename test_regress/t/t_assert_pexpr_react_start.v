// DESCRIPTION: Verilator: Assertion controls apply to concurrent assertion attempts by start
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__, `__LINE__, (gotv), (expv)); `stop; end while (0);
// verilog_format: on

// IEEE 1800-2023 20.11: PassOff and FailOff do not affect an attempt already executing, Kill
// aborts the attempts executing, and Off starts no new attempts.
// p until q fails at tick 3 for the attempts of ticks 0-3, at tick 8 for those of ticks 6-8,
// and passes at tick 5 for those of ticks 4-5 (IEEE 1800-2023 16.12.12). Controls, between
// ticks: FailOff after tick 1, FailOn after 3, PassOff after 4, PassOn after 5, Kill after 6,
// On after 7. So the attempts of ticks 0-1 fail at 3, that of tick 4 passes at 5, that of tick
// 6 is aborted, that of tick 7 does not start, and that of tick 8 fails at 8.
module t;
  localparam int T = 10;
  localparam bit P[T] = '{1, 1, 1, 0, 1, 1, 1, 1, 0, 1};
  localparam bit Q[T] = '{0, 0, 0, 0, 0, 1, 0, 0, 0, 0};
  localparam int NFAIL[T] = '{0, 0, 0, 2, 0, 0, 0, 0, 1, 0};
  localparam int NPASS[T] = '{0, 0, 0, 0, 0, 1, 0, 0, 0, 0};

  bit clk = 0;
  int cyc = 0;
  bit p = P[0];
  bit q = Q[0];
  int nfail = 0;
  int npass = 0;
  int exp_nfail = 0;
  int exp_npass = 0;

  assert property (@(posedge clk) p until q) ++npass;
  else ++nfail;
  // Without coverage, a cover statement is deleted, with its action
  int ncov = 0;
  cover property (@(posedge clk) p until q) ++ncov;

  always #5 clk = ~clk;
  always @(posedge clk) cyc <= cyc + 1;

  always @(negedge clk) begin
    exp_nfail += NFAIL[cyc-1];
    exp_npass += NPASS[cyc-1];
    `checkd(nfail, exp_nfail);
    `checkd(npass, exp_npass);
    case (cyc - 1)
      1: $assertcontrol(9);
      3: $assertcontrol(8);
      4: $assertcontrol(7);
      5: $assertcontrol(6);
      6: $assertcontrol(5);
      7: $assertcontrol(3);
      default: ;
    endcase
    if (cyc < T) begin
      p = P[cyc];
      q = Q[cyc];
    end
    else begin
      `checkd(exp_nfail, 3);
      `checkd(exp_npass, 1);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
