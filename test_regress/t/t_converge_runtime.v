// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Finite zero-time work that needs more scheduling iterations in one time
// slot than the default convergence limit allows (IEEE 1800-2023 4.5)

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module t;

  // A producer and a consumer exchange 30000 items through a bounded mailbox,
  // all at time 0
  mailbox #(int) mb = new(1);
  longint sum = 0;
  int cnt = 0;
  initial begin
    fork
      for (int i = 0; i < 30000; ++i) mb.put(i);
      begin
        int v;
        for (int i = 0; i < 30000; ++i) begin
          mb.get(v);
          sum += 64'(v);
          ++cnt;
        end
      end
    join
    `checkd($time, 0);
    `checkd(cnt, 30000);
    `checkd(sum, 64'd449985000);
  end

  // A combinational ring that settles once every stage saturates at cap
  int cap = 200000;
  int v0, v1, v2, v3, v4, v5, v6, v7;
  // verilator lint_off UNOPTFLAT
  always_comb v0 = (v7 + 1 > cap) ? cap : v7 + 1;
  always_comb v1 = (v0 + 1 > cap) ? cap : v0 + 1;
  always_comb v2 = (v1 + 1 > cap) ? cap : v1 + 1;
  always_comb v3 = (v2 + 1 > cap) ? cap : v2 + 1;
  always_comb v4 = (v3 + 1 > cap) ? cap : v3 + 1;
  always_comb v5 = (v4 + 1 > cap) ? cap : v4 + 1;
  always_comb v6 = (v5 + 1 > cap) ? cap : v5 + 1;
  always_comb v7 = (v6 + 1 > cap) ? cap : v6 + 1;
  // verilator lint_on UNOPTFLAT
  initial begin
    #1;
    `checkd(v0, 200000);
    `checkd(v3, 200000);
    `checkd(v7, 200000);
    `checkd(cnt, 30000);
    $write("*-* All Finished *-*\n");
    $finish;
  end

endmodule
