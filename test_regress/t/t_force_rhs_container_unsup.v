// DESCRIPTION: Verilator: whole dynamic values in force RHS change tracking
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;
  typedef logic [6:0] word_t;
  typedef word_t queue_t[$];
  typedef word_t vector_t[];
  typedef queue_t queue_bank_t[2];
  typedef vector_t vector_bank_t[2];
  queue_t q;
  queue_bank_t queue_bank;
  vector_bank_t vector_bank;
  word_t dst, qsum, vsum;
  function automatic word_t total(queue_t value);
    return word_t'(value.size());
  endfunction
  function automatic word_t total_q(queue_bank_t value);
    return word_t'(value[0].size());
  endfunction
  function automatic word_t total_v(vector_bank_t value);
    return word_t'(value[0].size());
  endfunction
  initial begin
    force dst = total(q);
    force qsum = total_q(queue_bank);
    force vsum = total_v(vector_bank);
  end
endmodule
