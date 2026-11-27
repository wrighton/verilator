// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// An $assertkill ends the attempts executing when it is called, and not an attempt starting
// after it, at the next clock event (IEEE 1800-2023 20.11). Attempts start at ticks K-1 and K;
// each row kills them at a different point.
module row #(
    parameter int MODE = 0
) (
    input clk,
    input int cyc
);
  localparam int K = 5;
  wire a = cyc == K - 1 || cyc == K;
  int pass_n = 0, fail_n = 0, range_n = 0, and_n = 0, not_n = 0, cpass_n = 0, cnot_n = 0;
  assert property (@(posedge clk) a |-> ##2 1'b1) ++pass_n;
  assert property (@(posedge clk) a |-> ##2 1'b0)
  else ++fail_n;
  assert property (@(posedge clk) a |-> ##[2:3] cyc == K + 3) ++range_n;
  else;
  // An 'and' of sequences ending on different ticks
  assert property (@(posedge clk) a |-> (##1 1'b1) and (##2 1'b1)) ++and_n;
  // A property operator over the consequent
  assert property (@(posedge clk) a |-> not (##2 1'b0)) ++not_n;
  // Test: attempts on every tick, with no input changing at the kill
  assert property (@(posedge clk) 1'b1 |-> ##2 1'b1) ++cpass_n;
  assert property (@(posedge clk) 1'b1 |-> not (##2 1'b0)) ++cnot_n;
  initial $assertvacuousoff(0, row);
  // Test: killed between the ticks of the two attempts
  task automatic kill();
    $assertkill(0, row);
    $asserton(0, row);
  endtask
  if (MODE == 0) always @(negedge clk) if (cyc == K) kill();
  // Test: killed on the edge of the second attempt after it is evaluated, by an action block.
  // A kill by a procedure on that edge, before the assertions are evaluated in the Observed
  // region, is not ordered against their evaluation.
  if (MODE == 1) begin
    assert property (@(posedge clk) cyc != K)
    else kill();
  end
endmodule

// Killed by a procedure on the clock edge of the assertion, repeatedly. It ends the attempts on
// the next clock event, as if after the evaluation on the edge: Verilator evaluates assertions
// with the procedures of the edge, not after them in the Observed region (IEEE 1800-2023 4.4.2.6,
// 16.14.6), so this differs from the standard. The result does not depend on the threads.
module own (
    input clk,
    input int cyc
);
  localparam int N = 60;
  bit [30:0] lfsr = 31'h1234_5679;
  always @(posedge clk) lfsr <= {lfsr[29:0], lfsr[30] ^ lfsr[27]};
  wire a = lfsr[3] | lfsr[7];
  wire b = lfsr[9];
  wire kill = cyc % 7 == 5;
  int fail_n = 0;
  assert property (@(posedge clk) a |-> ##2 b)
  else ++fail_n;
  always @(posedge clk) begin
    if (kill) begin
      $assertkill(0, own);
      $asserton(0, own);
    end
  end
  bit ah[N], bh[N], kh[N];
  always @(posedge clk) begin
    if (cyc < N) begin
      ah[cyc] = a;
      bh[cyc] = b;
      kh[cyc] = kill;
    end
  end
  // Failures of the attempts of ticks before n - 2, each ended by a kill on its tick or the next
  function automatic int expFails(int n);
    int count = 0;
    for (int s = 0; s + 2 < n; ++s) begin
      if (ah[s] && !bh[s+2] && !kh[s] && !kh[s+1]) ++count;
    end
    return count;
  endfunction
endmodule

module t (
    input clk
);
  int cyc = 0;
  always @(posedge clk) cyc <= cyc + 1;

  row #(.MODE(0)) row0 (.*);
  row #(.MODE(1)) row1 (.*);
  own u_own (.*);

  always @(negedge clk) begin
    if (cyc == 12) begin
      // Only the attempt of tick K runs, then passes, fails or passes at its last tick
      `checkd(row0.pass_n, 1);
      `checkd(row0.fail_n, 1);
      `checkd(row0.range_n, 1);
      `checkd(row0.and_n, 1);
      `checkd(row0.not_n, 1);
      // Of the attempts of ticks 0 to 9, those of ticks K-2 and K-1 are in flight at the kill
      `checkd(row0.cpass_n, 8);
      `checkd(row0.cnot_n, 8);
      // Both attempts execute at the kill
      `checkd(row1.pass_n, 0);
      `checkd(row1.fail_n, 0);
      `checkd(row1.range_n, 0);
      `checkd(row1.and_n, 0);
      `checkd(row1.not_n, 0);
      // Those of ticks K-1 and K are in flight at the kill
      `checkd(row1.cpass_n, 8);
      `checkd(row1.cnot_n, 8);
    end
    if (cyc == u_own.N + 2) begin
      `checkd(u_own.fail_n, u_own.expFails(u_own.N));
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
