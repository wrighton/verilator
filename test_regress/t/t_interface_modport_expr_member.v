// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Test modport expressions selecting struct/union members (unsupported)

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0x exp=%0x (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

typedef struct packed {
  logic [2:0] a;
  logic [4:0] b;
} inner_t;

typedef struct packed {
  logic [6:0] x;
  inner_t in;
} outer_t;

typedef union packed {
  logic [7:0] w;
  inner_t s;
} un_t;

interface my_if;
  outer_t s;
  un_t u;

  modport mp(input .ix(s.x), input .ia(s.in.a), input .uw(u.w), output .ob(s.in.b));
endinterface

module mod (
    my_if.mp i,
    output logic [6:0] ox,
    output logic [2:0] oa,
    output logic [7:0] ow
);
  assign ox = i.ix;
  assign oa = i.ia;
  assign ow = i.uw;
  assign i.ob = i.ix[4:0] ^ 5'h15;
endmodule

module top ();
  my_if myIf ();
  logic [6:0] ox;
  logic [2:0] oa;
  logic [7:0] ow;

  mod modInstance (myIf, ox, oa, ow);

  initial begin
    for (int n = 0; n < 3; ++n) begin
      myIf.s.x = 7'(n * 37 + 5);
      myIf.s.in.a = 3'(n * 3 + 1);
      myIf.u.w = 8'(n * 71 + 9);
      #1;
      `checkh(ox, 7'(n * 37 + 5));
      `checkh(oa, 3'(n * 3 + 1));
      `checkh(ow, 8'(n * 71 + 9));
      `checkh(myIf.s.in.b, 5'(n * 37 + 5) ^ 5'h15);
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
