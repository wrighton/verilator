// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkp(gotv,expv_s) do begin string gotv_s; gotv_s = $sformatf("%p", gotv); if ((gotv_s) != (expv_s)) begin $write("%%Error: %s:%0d:  got='%s' exp='%s'\n", `__FILE__,`__LINE__, (gotv_s), (expv_s)); `stop; end end while(0);
// verilog_format: on

// Whole unpacked arrays assigned through an impure side, which must not be
// evaluated once per element
module t (
    input clk
);
  typedef int pair_t[2];

  int cyc = 0;
  pair_t p;
  pair_t pa[int];
  pair_t pw[*];
  pair_t pq[$];

  always @(posedge clk) begin
    cyc <= cyc + 1;
    p = '{cyc, cyc + 1};
    // Writes to an associative array or queue element create it
    pa[cyc] = p;
    pw[cyc] = p;
    pq.push_back(p);
    pq[cyc] = '{cyc + 2, cyc + 3};
    if (cyc == 3) begin
      `checkp(pa, "'{'h0:'{'h0, 'h1}, 'h1:'{'h1, 'h2}, 'h2:'{'h2, 'h3}, 'h3:'{'h3, 'h4}}");
      `checkp(pw[3], "'{'h3, 'h4}");
      // A popped element is read once
      p = pq.pop_front();
      `checkp(p, "'{'h2, 'h3}");
      `checkp(pq, "'{'{'h3, 'h4}, '{'h4, 'h5}, '{'h5, 'h6}}");
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
