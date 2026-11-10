// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder and Contributors
// SPDX-License-Identifier: CC0-1.0

`timescale 1ps / 100fs
module reset_fine (
    output bit done
);
  initial begin
    realtime start;
    bit [6:0] phase;
    done = 0;
    for (int turn = 0; turn < 3; ++turn) begin
      phase = 7'(3 + turn);
      start = $realtime;
      #(phase);
      `checkr($realtime - start, real'(phase));
      start = $realtime;
      #0.15;
      `checkr($realtime - start, 0.2);
    end
    done = 1;
  end
endmodule

module reset_keyword_before (
    output bit done
);
  timeunit 1ps; timeprecision 100fs;
  initial begin
    realtime start;
    bit [6:0] phase;
    done = 0;
    for (int turn = 0; turn < 3; ++turn) begin
      phase = 7'(5 + turn);
      start = $realtime;
      #(phase);
      `checkr($realtime - start, real'(phase));
      start = $realtime;
      #0.15;
      `checkr($realtime - start, 0.2);
    end
    done = 1;
  end
endmodule

`resetall
