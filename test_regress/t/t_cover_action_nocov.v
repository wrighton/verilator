// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv, expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// The pass statement of a cover runs without coverage collection too (IEEE 1800-2023 16.3,
// 16.14.3); a cover with no pass statement is still removed.
module t (
    input clk
);
  int cyc = 0;
  always @(posedge clk) cyc <= cyc + 1;
  wire c = cyc[0];
  wire d = cyc[1];

  int n_bool = 0, n_seq = 0, n_imp = 0, n_covseq = 0, n_ev = 0, n_imm = 0, n_def = 0;
  int ref_bool = 0, ref_seq = 0, ref_imp = 0, ref_covseq = 0, ref_ev = 0;
  bit c1 = 0;
  always @(posedge clk) c1 <= c;

  cover property (@(posedge clk) c) n_bool++;
  cover property (@(posedge clk) c ##1 d) n_seq++;
  cover property (@(posedge clk) c |=> d) n_imp++;
  // Each end of a match runs it, here ending on the tick of c or on the next
  cover sequence (@(posedge clk) c ##[0:1] d) n_covseq++;
  // A property expression whose pass statement runs from more than one place
  cover property (@(posedge clk) s_eventually c) n_ev++;
  always @(posedge clk) begin
    ref_bool += int'(c);
    ref_seq += int'(c1 && d);
    ref_imp += int'(c1 && d);
    ref_covseq += int'(c && d) + int'(c1 && d);
    // The attempts of this tick and, if c did not hold then, of the previous one
    ref_ev += int'(c) * (1 + int'(!c1));
  end

  function void count_def();
    n_def++;
  endfunction
  always @(posedge clk) begin
    cover (c) n_imm++;
    cover #0 (c) count_def();
  end

  // The pass statement runs in the Reactive region, after the NBA updates of its tick
  int q = 0, n_late = 0, n_late_seq = 0;
  always @(posedge clk) q <= q + 1;
  cover property (@(posedge clk) $c32("1") == 1) n_late += int'(q == $sampled(q) + 1);
  cover property (@(posedge clk) $c32("1") == 1 ##1 $c32("1") == 1)
    n_late_seq += int'(q == $sampled(q) + 1);

  // A pass statement reading $past stays where it is
  int n_past = 0;
  cover property (@(posedge clk) c) n_past += int'(!$past(c));

  // No pass statement: removed, so its expression is not in the model
  cover property (@(posedge clk) $c32("1 /*VL_NOACTION_COVER*/") == 1);
  int n_marker = 0;
  cover property (@(posedge clk) $c32("1 /*VL_ACTION_COVER*/") == 1) n_marker++;

  always @(negedge clk) begin
    if (cyc == 40) begin
      `checkd(n_bool, ref_bool);
      `checkd(n_seq, ref_seq);
      `checkd(n_imp, ref_imp);
      `checkd(n_covseq, ref_covseq);
      `checkd(n_ev, ref_ev);
      `checkd(n_imm, ref_bool);
      `checkd(n_def, ref_bool);
      `checkd(n_marker, 40);
      `checkd(n_late, 40);
      `checkd(n_late_seq, 39);
      `checkd(n_past, ref_bool);
      `checkd(ref_bool, 20);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
