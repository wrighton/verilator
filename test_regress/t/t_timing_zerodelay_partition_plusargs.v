// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// A command line argument added by C code called by a clocked process is seen after a #0 in
// the same time step

module t (
    input bit clk,
    output int got_test,
    output int got_value
);
  import "DPI-C" function void addarg();
  int x;
  always @(posedge clk) addarg();
  always @(posedge clk) begin
    #0;
    got_test = $test$plusargs("reviewflag");
    got_value = $value$plusargs("reviewflag=%d", x) != 0 ? x : -1;
  end
endmodule
