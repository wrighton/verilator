// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder and Contributors
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkr(gotv, expv) do if (((gotv) - (expv) > 1e-6) || ((expv) - (gotv) > 1e-6)) begin $write("%%Error: %s:%0d: got=%g exp=%g\n", `__FILE__, `__LINE__, (gotv), (expv)); `stop; end while (0);
// verilog_format: on

`resetall
`timescale 10ns / 1ns
`resetall

module t;
  timeunit 1ns; timeprecision 1ps;
  wire early_done, fine_done, keyword_before_done, default_done;
  wire keyword_after_done, directive_done, trailing_done;

  reset_early early (early_done);
  reset_fine fine (fine_done);
  reset_keyword_before keyword_before (keyword_before_done);
  reset_default_after default_after (default_done);
  reset_keyword_after keyword_after (keyword_after_done);
  reset_directive_after directive_after (directive_done);
  reset_trailing_default trailing_default (trailing_done);

  initial begin
    realtime start;
    start = $realtime;
    // A legal later reset cannot erase the earlier modules' 100fs global minimum.
    #1step;
    `checkr($realtime - start, 0.0001);
    wait (early_done && fine_done && keyword_before_done && default_done
          && keyword_after_done && directive_done && trailing_done);
    $write("*-* All Finished *-*\n");
    $finish;
  end

  initial begin
    #100ns;
    `stop;
  end
endmodule

// An early reset restores the CLI's 1ns/1ps directive defaults.
module reset_early (
    output bit done
);
  initial begin
    realtime one_ns;
    realtime start;
    bit [6:0] phase;
    done = 0;
    one_ns = 1ns;
    `checkr(one_ns, 1.0);
    for (int turn = 0; turn < 3; ++turn) begin
      phase = 7'(3 + turn);
      start = $realtime;
      #(phase);
      `checkr($realtime - start, real'(phase));
    end
    done = 1;
  end
endmodule

// The included file supplies fine modules and ends with a legal outside-scope reset.
`include "t_timescale_resetall_fine.vh"

module reset_default_after (
    output bit done
);
  initial begin
    realtime one_ns;
    realtime start;
    bit [6:0] phase;
    done = 0;
    one_ns = 1ns;
    `checkr(one_ns, 1.0);
    for (int turn = 0; turn < 3; ++turn) begin
      phase = 7'(5 + turn);
      start = $realtime;
      #(phase);
      `checkr($realtime - start, real'(phase));
    end
    done = 1;
  end
endmodule

// Explicit keywords still override the reset directive defaults.
module reset_keyword_after (
    output bit done
);
  timeunit 10ps; timeprecision 1ps;
  initial begin
    realtime one_ns;
    realtime start;
    bit [6:0] phase;
    done = 0;
    one_ns = 1ns;
    `checkr(one_ns, 100.0);
    for (int turn = 0; turn < 3; ++turn) begin
      phase = 7'(7 + turn);
      start = $realtime;
      #(phase);
      `checkr($realtime - start, real'(phase));
    end
    done = 1;
  end
endmodule

// A subsequent timescale overrides the reset directive defaults as before.
`timescale 100ps / 1ps
module reset_directive_after (
    output bit done
);
  initial begin
    realtime one_ns;
    realtime start;
    bit [6:0] phase;
    done = 0;
    one_ns = 1ns;
    `checkr(one_ns, 10.0);
    for (int turn = 0; turn < 3; ++turn) begin
      phase = 7'(9 + turn);
      start = $realtime;
      #(phase);
      `checkr($realtime - start, real'(phase));
    end
    done = 1;
  end
endmodule

`resetall
module reset_trailing_default (
    output bit done
);
  initial begin
    realtime one_ns;
    done = 0;
    one_ns = 1ns;
    `checkr(one_ns, 1.0);
    #1;
    done = 1;
  end
endmodule

// No later declaration may mask the lost global precision after this trailing reset.
`resetall
