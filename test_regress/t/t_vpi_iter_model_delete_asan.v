// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

interface ifc;
  logic [6:0] value;
endinterface

module sub (
    ifc port
);
  typedef struct packed {
    logic [2:0] a;
    logic [4:0] b;
  } pair_t;
  pair_t pair;
  logic [6:0] arr[3:1];
  always_comb begin
    pair = {port.value[2:0], port.value[4:0]};
    for (int i = 1; i <= 3; ++i) arr[i] = port.value + 7'(i);
  end
endmodule

module t (
    input clk
);
  ifc conn ();
  sub u (.port(conn));
  always @(posedge clk) conn.value <= conn.value + 1;
endmodule
