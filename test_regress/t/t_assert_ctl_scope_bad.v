// DESCRIPTION: Verilator: Invalid assertion control scope arguments
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;
  int not_a_scope = 0;
  initial begin
    $assertoff(0, not_a_scope);
    $assertoff(0, missing_scope);
    $assertoff(0, not_a_scope + 1);
  end
endmodule
