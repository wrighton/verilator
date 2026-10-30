// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

typedef struct {
  int a;
} st_t;

module t;
  mailbox m = new;

  initial begin
    int arr[2];
    int q[$];
    st_t st;
    m.put(arr);  // Bad, not singular
    void'(m.try_put(st));  // Bad, not singular
    m.get(q);  // Bad, not singular
  end
endmodule
