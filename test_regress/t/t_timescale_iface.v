// DESCRIPTION: Verilator: Interface directive timing metadata
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define clock_body \
  bit start; \
  bit clk; \
  bit [14:0] high_phase; \
  bit [14:0] low_phase; \
  initial begin \
    wait (start); \
    for (int cycle = 0; cycle < 4; ++cycle) begin \
      #(high_phase + cycle) clk = 1; \
      #(low_phase + cycle) clk = 0; \
    end \
  end
// verilog_format: on

// Place the ns scope first so a missing interface directive cannot use the ps
// module control as its fallback unit.
module t;
  timeunit 1ns; timeprecision 1ns;
  directive_clock directive_if ();
  keyword_clock keyword_if ();
  module_clock module_control ();
  precision_probe precision_if ();
  wire directive_done, keyword_done, module_done;
  check_clock check_directive (
      directive_if.clk,
      directive_done
  );
  check_clock check_keyword (
      keyword_if.clk,
      keyword_done
  );
  check_clock check_module (
      module_control.clk,
      module_done
  );

  initial begin
    directive_if.high_phase = 700;
    directive_if.low_phase = 1300;
    keyword_if.high_phase = 700;
    keyword_if.low_phase = 1300;
    module_control.high_phase = 700;
    module_control.low_phase = 1300;
    directive_if.start = 1;
    keyword_if.start = 1;
    module_control.start = 1;
  end

  initial begin
    wait (precision_if.done);
    // A 0.15ps delay rounds to 0.2ps, despite the top's coarser precision.
    `checkd($realtime > 0.000199 && $realtime < 0.000201, 1);
    wait (directive_done && keyword_done && module_done);
    $write("*-* All Finished *-*\n");
    $finish;
  end

  initial begin
    #20;
    `stop;
  end
endmodule

module check_clock (
    input bit clk,
    output bit done
);
  timeunit 1ns; timeprecision 1ns;
  initial begin
    realtime previous_edge, interval, expected;
    @(posedge clk);
    previous_edge = $realtime;
    for (int cycle = 1; cycle < 4; ++cycle) begin
      @(posedge clk);
      interval = $realtime - previous_edge;
      expected = (1999.0 + 2.0 * cycle) / 1000.0;
      `checkd(interval > expected - 0.000001 && interval < expected + 0.000001, 1);
      previous_edge = $realtime;
    end
    done = 1;
  end
endmodule

`timescale 1ps / 100fs
interface directive_clock;
  `clock_body
endinterface

`timescale 1ps / 1ps
interface keyword_clock;
  timeunit 1ps; timeprecision 1ps;
  `clock_body
endinterface

module module_clock;
  `clock_body
endmodule

`timescale 1ps / 100fs
interface precision_probe;
  bit done;
  initial begin
    #0.15;
    done = 1;
  end
endinterface

`undef clock_body
