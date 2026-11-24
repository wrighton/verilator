// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

interface force_target;
  wire value;
  assign (weak0, weak1) value = 1'b1;
endinterface

module t (
    input bit rhs,
    input bit take,
    drop,
    output bit value,
    output bit floating
);
  force_target target ();
  always @(posedge take) force target.value = rhs;
  always @(posedge drop) release target.value;
  assign value = target.value;
  assign floating = target.value === 1'bz;
endmodule
