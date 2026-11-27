// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv, expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Without coverage collection, the pass statement of a multi-cycle cover follows the pass
// control as with it (IEEE 1800-2023 20.11)
module t (
    input clk
);
  int cyc = 0;
  always @(posedge clk) cyc <= cyc + 1;
  wire a = cyc[0];
  wire b = cyc[1] ^ cyc[2];

  bit on = 1;
  always @(negedge clk) begin
    if (cyc == 10) begin
      $assertpassoff;
      on = 0;
    end
    if (cyc == 20) begin
      $assertpasson;
      on = 1;
    end
  end

  int n_seq = 0, n_imp = 0, n_covseq = 0;
  int ref_seq = 0, ref_covseq = 0, all_seq = 0;
  bit a1 = 0, a2 = 0;
  always @(posedge clk) begin
    a1 <= a;
    a2 <= a1;
  end

  cover property (@(posedge clk) a ##1 b) n_seq++;
  cover property (@(posedge clk) a |-> ##1 b) n_imp++;
  cover sequence (@(posedge clk) a ##[1:2] b) n_covseq++;
  always @(posedge clk) begin
    all_seq += int'(a1 && b);
    if (on) begin
      ref_seq += int'(a1 && b);
      ref_covseq += int'(a1 && b) + int'(a2 && b);
    end
  end

  always @(negedge clk) begin
    if (cyc == 40) begin
      `checkd(n_seq, ref_seq);
      `checkd(n_imp, ref_seq);
      `checkd(n_covseq, ref_covseq);
      // Some passed while the pass control was off
      `checkd(all_seq > ref_seq, 1'b1);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
