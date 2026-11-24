// DESCRIPTION: Verilator: whole dynamic values in force RHS change tracking
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;
  typedef logic [6:0] word_t;
  typedef word_t queue_t[$];
  queue_t q;
  word_t dst;
  function automatic word_t total(queue_t value);
    return word_t'(value.size());
  endfunction
  initial force dst = total(q);
endmodule
