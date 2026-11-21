// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define checks(gotv,expv) do if ((gotv) != (expv)) begin $write("%%Error: %s:%0d:  got='%s' exp='%s'\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// A static process that a handle keeps is not current once its procedure returns, so code
// without a process of its own does not draw from its RNG (IEEE 1800-2023 18.14.1). There is no
// timing here, as starting a process with timing draws from the current process.

module t;
  process kept;
  string keptState;
  bit keptDone;
  initial begin
    kept = process::self();
    kept.srandom(42);
    keptState = kept.get_randstate();
    keptDone = 1'b1;
  end

  // Draws while settling, after the initial blocks
  int unsigned settleDrawn;
  bit settleDrew;
  always_comb begin
    settleDrawn = keptDone ? $urandom : 0;
    settleDrew = keptDone;
  end

  final begin
    `checks(kept.get_randstate(), keptState);
    `checkh(settleDrew, 1'b1);
    // Uses the value drawn, so the draw is kept
    $display("Settled with %0d", settleDrawn);
    $write("*-* All Finished *-*\n");
  end
endmodule
