// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

// The sampled value of the triggered method of an event is its current value, and a past value
// is that at the end of the past clock tick (IEEE 1800-2023 16.5.1, 15.5.3)

module t (
    input clk
);
  localparam int NCYC = 40;
  int unsigned crc = 32'h1;
  int cyc = 0;
  int n_fired = 0;
  event e;

  // Triggered in the Active region of the ticks crc[0] is sampled set on
  always @(posedge clk) begin
    if (crc[0]) begin
      ->e;
      ++n_fired;
    end
    cyc <= cyc + 1;
    crc <= {crc[30:0], crc[31] ^ crc[21] ^ crc[1] ^ crc[0]};
    if (cyc == NCYC) $finish;
  end

  int n_mismatch = 0;
  assert property (@(posedge clk) e.triggered == crc[0])
  else ++n_mismatch;

  int n_triggered = 0;
  assert property (@(posedge clk) !e.triggered)
  else ++n_triggered;

  int n_past_mismatch = 0;
  assert property (@(posedge clk) ##1 $past(e.triggered) == $past(crc[0]))
  else ++n_past_mismatch;

  final begin
    `checkd(n_mismatch, 0);
    `checkd(n_triggered, n_fired);
    `checkd(n_past_mismatch, 0);
    `checkd(n_fired > NCYC / 4, 1);
    $write("*-* All Finished *-*\n");
  end
endmodule
