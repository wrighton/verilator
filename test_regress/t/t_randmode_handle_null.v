// DESCRIPTION: Verilator: Cloned constraint modes must not dereference null owners
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Michael Wrighton
// SPDX-License-Identifier: CC0-1.0

// Use the existing Item/Holder definitions. The isolated test top keeps this
// mode-getter regression separate from pre-existing full-top null-c_w behavior.
`include "t_randomize_rand_mode_handle.v"

module t_null_mode;
  initial begin
    Holder h;
    int result;
    h = new;
    h.c.c_v.constraint_mode(1);
    h.c = null;
    result = h.randomize();
    `checkd(result, 0);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
