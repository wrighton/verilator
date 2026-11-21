// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// An 'else' after an assertion with a null pass statement belongs to the enclosing 'if'
// (IEEE 1800-2023 16.3, A.6.3)

module t (
    input clk
);
  int cyc = 0;
  // Each 'else' below runs when cyc is even, so ten times over cycles 1 to 20
  int simple_hits = 0, assume_hits = 0, deferred_hits = 0, final_hits = 0;
  int assume_deferred_hits = 0, assume_final_hits = 0;
  int property_hits = 0, assume_property_hits = 0;

  always @(posedge clk) begin
    ++cyc;
    if (cyc[0]) assert (cyc > 0);
    else ++simple_hits;
    if (cyc[0]) assume (cyc > 0);
    else ++assume_hits;
    if (cyc[0]) assert property (cyc > 0);
    else ++property_hits;
    if (cyc[0]) assume property (cyc > 0);
    else ++assume_property_hits;
    if (cyc == 21) begin
      `checkd(simple_hits, 10);
      `checkd(assume_hits, 10);
      `checkd(deferred_hits, 10);
      `checkd(final_hits, 10);
      `checkd(assume_deferred_hits, 10);
      `checkd(assume_final_hits, 10);
      `checkd(property_hits, 10);
      `checkd(assume_property_hits, 10);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end

  always @(cyc) begin
    if (cyc[0] || cyc > 20) assert #0 (cyc > 0);
    else ++deferred_hits;
    if (cyc[0] || cyc > 20) assert final (cyc > 0);
    else ++final_hits;
    if (cyc[0] || cyc > 20) assume #0 (cyc > 0);
    else ++assume_deferred_hits;
    if (cyc[0] || cyc > 20) assume final (cyc > 0);
    else ++assume_final_hits;
  end
endmodule
