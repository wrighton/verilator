// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;
  // Each call passing a large array to a constant function must not copy it
  localparam int N = 4096;
  typedef int tbl_t[N];
  function automatic int get(tbl_t tbl, int i);
    return tbl[i];
  endfunction
  function automatic int total();
    tbl_t tbl;
    int s = 0;
    foreach (tbl[i]) tbl[i] = i % 7;
    for (int i = 0; i < N; ++i) s += get(tbl, i);
    return s;
  endfunction
  localparam int TOTAL = total();
  if (TOTAL != 12285) begin : g_bad
    $error("TOTAL=%0d", TOTAL);
  end

  // Matching array types declared independently, one with an explicit range
  function automatic int get_decl(int tbl[0:N-1], int i);
    return tbl[i];
  endfunction
  function automatic int total_decl();
    int tbl[N];
    int s = 0;
    foreach (tbl[i]) tbl[i] = i % 5;
    for (int i = 0; i < N; ++i) s += get_decl(tbl, i);
    return s;
  endfunction
  localparam int TOTAL_DECL = total_decl();
  if (TOTAL_DECL != 8190) begin : g_bad_decl
    $error("TOTAL_DECL=%0d", TOTAL_DECL);
  end

  // A static variable, of a function with the default lifetime
  function int total_static();
    tbl_t tbl;
    int s;
    s = 0;
    foreach (tbl[i]) tbl[i] = i % 3;
    for (int i = 0; i < N; ++i) s += get(tbl, i);
    return s;
  endfunction
  localparam int TOTAL_STATIC = total_static();
  if (TOTAL_STATIC != 4095) begin : g_bad_static
    $error("TOTAL_STATIC=%0d", TOTAL_STATIC);
  end

endmodule
