// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Solved array sizes come out uniform over the range constraining them, as other
// variables do, whatever solver finds them

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

class ForeachDims;
  rand bit [7:0] m[][2][3];
  rand bit [7:0] q[$];
  rand bit [7:0] z[3];
  constraint c {
    m.size() inside {[1 : 3]};
    foreach (m[i, j, k]) {
      m[i][j][k] == 8'(i * 6 + j * 3 + k + 1);
      z[k] == 8'(k + 8'h70);
    }
  }
  constraint c_if {
    q.size() inside {[1 : 3]};
    if (q.size() > 0) {
      foreach (q[i]) q[i] == 8'(i + 8'h80);
    }
  }
endclass

module t;
  localparam int CALLS = 300;

  // Chi-square of counts over sizes 1 to 3, expected uniform: past 13.8 with 2 degrees of
  // freedom, one time in a thousand
  function automatic real chiSquare(int counts[4]);
    automatic real chi = 0.0;
    for (int s = 1; s <= 3; ++s) begin
      automatic real d = real'(counts[s]) - real'(CALLS) / 3.0;
      chi += d * d / (real'(CALLS) / 3.0);
    end
    return chi;
  endfunction

  initial begin
    automatic ForeachDims o = new;
    automatic int mc[4];
    automatic int qc[4];
    automatic int randomize_result;
    repeat (CALLS) begin
      randomize_result = o.randomize();
      `checkd(randomize_result, 1);
      `checkd(o.m.size() inside {[1 : 3]}, 1'b1);
      `checkd(o.q.size() inside {[1 : 3]}, 1'b1);
      foreach (o.m[i, j, k]) `checkd(o.m[i][j][k], 8'(i * 6 + j * 3 + k + 1));
      foreach (o.q[i]) `checkd(o.q[i], 8'(i + 8'h80));
      mc[o.m.size()]++;
      qc[o.q.size()]++;
    end
    if (chiSquare(mc) > 13.8 || chiSquare(qc) > 13.8) begin
      $write("%%Error: sizes m %0d/%0d/%0d q %0d/%0d/%0d\n", mc[1], mc[2], mc[3], qc[1], qc[2],
             qc[3]);
      `stop;
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
