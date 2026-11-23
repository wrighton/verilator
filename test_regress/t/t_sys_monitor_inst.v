// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

package pkg;
  int pv = 5;
  function automatic void pmon();
    $monitor("[%0t] pkg pv=%0d", $time, pv);
  endfunction
endpackage

module sub (
    input bit start,
    input int value
);
  always @(posedge start) $monitor("[%0t] %m value=%0d", $time, value);
endmodule

module t;

  // A $monitor invoked by a static initializer
  function automatic int install();
    $monitor("[%0t] startup", $time);
    return 7;
  endfunction
  int initialized = install();

  bit start_a, start_b;
  int a = 11, b = 22;

  // Two instances of the same $monitor call: only the instance that called it last is monitored
  sub u_a (
      start_a,
      a
  );
  sub u_b (
      start_b,
      b
  );

  // The same $monitor call in two generate iterations
  int g = 0;
  for (genvar i = 0; i < 2; ++i) begin : gen
    initial #(70 + 10 * i) $monitor("[%0t] gen %0d g=%0d", $time, i, g);
  end

  initial begin
    #10 start_a = 1;
    #10 b = 23;
    #10 a = 12;
    #10 start_b = 1;
    #10 a = 13;
    #10 b = 24;
    #25 g = 1;
    #10 pkg::pmon();
    #5 g = 2;
    #5 pkg::pv = 6;
    #10;
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
