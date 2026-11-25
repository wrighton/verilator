// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Simulation finishes while a process holding a large object waits at a join; destroying the
// model must free the object

class Payload;
  int data[262143];
endclass

module t;
  event never;

  initial begin
    automatic Payload p = new;
    p.data[1] = 1;
    fork
      @never;
      #3;
    join
    p.data[2] = 2;
  end

  initial #1 $finish;
endmodule
