// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

// Module-level deferred assertions whose actions count their reports. Such an assertion is in an
// always_comb (IEEE 1800-2023 16.4), which is not sensitive to what its actions write (IEEE
// 1800-2023 9.2.2.2.1), so it reports once at time zero and once per change of a.
module t (
    input clk
);
  int cyc = 0;
  bit a = 0;

  int p_fin;
  int n_fin;
  int p_obs;
  int n_obs;
  function void bump_p_fin();
    p_fin++;
  endfunction
  function void bump_n_fin();
    n_fin++;
  endfunction
  function void bump_p_obs();
    p_obs++;
  endfunction
  function void bump_n_obs();
    n_obs++;
  endfunction

  assert final (a) bump_p_fin();
  else bump_n_fin();
`ifndef NO_TIMING  // Observed deferred assertions need --timing
  assert #0 (a) bump_p_obs();
  else bump_n_obs();
`endif

  always @(posedge clk) begin
    // Reports after cyc changes of a
    `checkd(p_fin, (cyc + 1) / 2);
    `checkd(n_fin, 1 + cyc / 2);
`ifndef NO_TIMING
    `checkd(p_obs, (cyc + 1) / 2);
    `checkd(n_obs, 1 + cyc / 2);
`endif
    cyc <= cyc + 1;
    a <= !a;
    if (cyc == 9) begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
