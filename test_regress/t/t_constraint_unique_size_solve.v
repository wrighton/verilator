// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Distinct elements of a solved size, fewer than the values for them, though the elements
// before are more
class Shrink;
  rand int q[$];
  constraint c {
    q.size() inside {[18 : 20]};
    unique {q};
    foreach (q[i]) q[i] inside {[0 : 29]};
  }
  function new;
    repeat (40) q.push_back(-1);
  endfunction
endclass

module t;
  int randomize_result;

  initial begin
    automatic Shrink s = new;
    repeat (3) begin
      automatic bit seen[int];
      randomize_result = s.randomize();
      `checkd(randomize_result, 1);
      `checkd(s.q.size() inside {[18 : 20]}, 1);
      foreach (s.q[i]) begin
        `checkd(s.q[i] inside {[0 : 29]}, 1);
        seen[s.q[i]] = 1;
      end
      `checkd(seen.size(), s.q.size());
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
