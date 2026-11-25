// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// rand_mode() of an unpacked struct whose members constraints name

typedef struct {
  rand bit [7:0] x;
  rand bit [7:0] y;
} inner_t;

typedef struct {
  rand bit [7:0] x;
  rand inner_t in;
} outer_t;

class WithStruct;
  rand outer_t s;
  rand bit [7:0] z;
  constraint c {
    s.x != 0;
    s.in.y > 8'd10;
    z == s.x;
  }
endclass

module t;
  initial begin
    automatic WithStruct ws = new;
    automatic bit changed = 0;
    ws.s.rand_mode(0);
    ws.s.x = 8'd5;
    ws.s.in.y = 8'd20;
    for (int i = 0; i < 20; ++i) begin
      if (ws.randomize() != 1) $stop;
      if (ws.z != 8'd5 || ws.s.x != 8'd5 || ws.s.in.y != 8'd20) $stop;
    end
    ws.s.rand_mode(1);
    for (int i = 0; i < 20; ++i) begin
      if (ws.randomize() != 1) $stop;
      if (ws.s.x == 0 || ws.s.in.y <= 8'd10 || ws.z != ws.s.x) $stop;
      if (ws.s.x != 8'd5) changed = 1;
    end
    if (!changed) $stop;
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
