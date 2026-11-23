// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// A net whose bits constant selects drive, one partly below it, forced on an interface
// strength net, is never high impedance
interface tgt_if;
  wire [1:0] value;
  assign (weak0, weak1) value = 2'b10;
endinterface

module t;
  tgt_if tgt ();
  bit lo = 1'b1;
  bit hi = 1'b1;
  wire [1:0] r;
  // verilator lint_off SELRANGE
  assign r[-1+:2] = {lo, lo};
  // verilator lint_on SELRANGE
  assign r[1] = hi;
  initial force tgt.value = r;
endmodule
