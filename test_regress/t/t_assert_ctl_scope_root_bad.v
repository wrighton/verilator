// DESCRIPTION: Verilator: Assertion control naming $root itself, not a scope below it
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;
  initial begin
    // A hierarchical_identifier needs an identifier after $root. (IEEE 1800-2023 Syntax 20-12)
    $assertoff(0, $root);
  end
endmodule
