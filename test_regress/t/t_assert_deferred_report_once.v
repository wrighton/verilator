// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

// A deferred assertion item is in an always_comb (IEEE 1800-2023 16.4), so runs, and reports,
// once at time zero and then once per change of what it reads (IEEE 1800-2023 9.2.2.2.2)
module t (
    input clk
);
  int cyc = 0;
  bit b = 0;  // Set once
  bit tg = 0;  // Changes on every third clock edge
  int tgChanges = 0;

  int obsPass = 0;
  int obsFail = 0;
  int finPass = 0;
  int finFail = 0;
  int tObsPass = 0;
  int tObsFail = 0;
  int tFinPass = 0;
  int tFinFail = 0;
  function void bumpObsPass();
    obsPass++;
  endfunction
  function void bumpObsFail();
    obsFail++;
  endfunction
  function void bumpFinPass();
    finPass++;
  endfunction
  function void bumpFinFail();
    finFail++;
  endfunction
  function void bumpTObsPass();
    tObsPass++;
  endfunction
  function void bumpTObsFail();
    tObsFail++;
  endfunction
  function void bumpTFinPass();
    tFinPass++;
  endfunction
  function void bumpTFinFail();
    tFinFail++;
  endfunction

  assert #0 (b) bumpObsPass();
  else bumpObsFail();
  assert final (b) bumpFinPass();
  else bumpFinFail();
  assert #0 (tg) bumpTObsPass();
  else bumpTObsFail();
  assert final (tg) bumpTFinPass();
  else bumpTFinFail();

  always @(tg) tgChanges++;

  always @(posedge clk) begin
    if (cyc > 0) begin
      // Failing at time zero, and passing once b is set
      `checkd(obsFail, 1);
      `checkd(obsPass, cyc >= 4 ? 1 : 0);
      `checkd(finFail, 1);
      `checkd(finPass, cyc >= 4 ? 1 : 0);
      // Failing at time zero and on each clear of tg, passing on each set
      `checkd(tObsPass, (tgChanges + 1) / 2);
      `checkd(tObsFail, 1 + tgChanges / 2);
      `checkd(tFinPass, (tgChanges + 1) / 2);
      `checkd(tFinFail, 1 + tgChanges / 2);
    end
    cyc <= cyc + 1;
    if (cyc == 3) b <= 1;
    if (cyc % 3 == 2) tg <= !tg;
    if (cyc == 20) begin
      `checkd(tgChanges, 6);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
