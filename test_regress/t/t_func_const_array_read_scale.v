// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;
  // Each read of a large array parameter in a constant function must not copy it
  localparam int N = 4096;
  typedef int tbl_t[N];
  function automatic tbl_t make();
    foreach (make[i]) make[i] = i % 7;
  endfunction
  localparam tbl_t TBL = make();
  function automatic int total();
    int s = 0;
    for (int i = 0; i < N; ++i) s += TBL[i];
    return s;
  endfunction
  localparam int TOTAL = total();
  if (TOTAL != 12285) begin : g_bad
    $error("TOTAL=%0d", TOTAL);
  end
endmodule
