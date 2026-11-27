// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// The sequence match items of an expression run only when it matches (IEEE 1800-2023 16.10,
// 16.11): not for an attempt whose expression does not hold, nor for one that already failed
module t;
  logic clk = 0;
  always #5 clk = ~clk;
  int cyc = 0;
  int d = 0;
  always @(posedge clk) begin
    cyc <= cyc + 1;
    d <= d + 1;
  end

  int calls[5];
  function automatic void inc(int k);
    ++calls[k];
  endfunction
  property p_never;
    int v;
    @(posedge clk) (cyc < 0, v = d, inc(0)) ##1 1 ##1 1;
  endproperty
  property p_first;
    int v;
    @(posedge clk) (cyc[0], v = d, inc(1)) ##1 1;
  endproperty
  property p_mid;
    @(posedge clk) cyc[0] ##1 (cyc[1], inc(2)) ##1 1;
  endproperty
  property p_bool;
    @(posedge clk) (cyc[1], inc(3));
  endproperty
  int fails[5];
  assert property (p_never)
  else fails[0]++;
  assert property (p_first)
  else fails[1]++;
  assert property (p_mid)
  else fails[2]++;
  assert property (p_bool)
  else fails[3]++;

  // Per-attempt oracle over the sampled values
  int exp_calls[5], exp_fails[5];
  int ch[$];
  always @(posedge clk) begin
    ch.push_back(cyc);
    if (!cyc[0]) ++exp_fails[2];
    if (ch.size() >= 2 && ch[ch.size()-2][0]) begin
      if (cyc[1]) ++exp_calls[2];
      else ++exp_fails[2];
    end
    if (cyc[0]) ++exp_calls[1];
    else ++exp_fails[1];
    if (cyc[1]) ++exp_calls[3];
    else ++exp_fails[3];
    ++exp_fails[0];
  end

  always @(negedge clk) begin
    if (cyc == 20) begin
      for (int k = 0; k < 4; ++k) begin
        `checkd(calls[k], exp_calls[k]);
        `checkd(fails[k], exp_fails[k]);
      end
      `checkd(exp_calls[1], 10);
      `checkd(exp_calls[2], 5);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
