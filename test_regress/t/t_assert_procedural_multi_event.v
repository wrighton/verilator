// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

// IEEE 1800-2023 16.14.6: the clock inferred for a procedure whose event control has several
// event expressions is the only edge or event expression whose variables the body does not
// otherwise use; sampled value functions (16.9.3) and procedural concurrent assertions in the
// procedure take that clock, not the other events.
module t;
  bit clock = 0;
  bit reset = 0;
  bit [6:0] d1 = 0;
  // Posedges at 5, 15, ..., 125; d1 changes at even times only; reset pulses between the
  // posedges at 75 and 85
  always #5 clock = ~clock;
  initial begin
    #2;
    forever begin
      d1 = d1 + 7'd3;
      #4;
    end
  end
  initial begin
    #81 reset = 1;
    #1 reset = 0;
  end
  // Model: d1 at the previous posedge
  bit [6:0] h1 = 0;
  always_ff @(posedge clock iff reset == 0) h1 <= d1;

  // Test: as the body reads reset, the inferred clock is 'posedge clock iff reset == 0'
  bit [6:0] q, cnt;
  always_ff @(posedge clock iff reset == 0 or posedge reset) begin
    cnt <= reset ? 0 : cnt + 1;
    q <= $past(d1);
  end
  always @(posedge clock iff reset == 0) begin
    automatic bit [6:0] exp_q = h1;
    #1;
    `checkd(q, exp_q);
  end

  // Test: an event variable is inferred as the clock
  event ev;
  always @(posedge clock) ->ev;
  bit [6:0] qe;
  always @(ev or posedge reset) begin
    if (reset) qe <= 0;
    else qe <= $past(d1);
  end
  always @(ev) begin
    automatic bit [6:0] exp_qe = h1;
    #1;
    `checkd(qe, exp_qe);
  end

  initial begin
    #131;
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
