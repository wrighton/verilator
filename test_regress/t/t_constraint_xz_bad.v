// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Constraints support only 2-state values (IEEE 1800-2023 18.3)

localparam logic [7:0] WILD = 8'b1???_0000;
localparam logic [7:0] UNKNOWN = 'x;

class FourState #(
    parameter logic [7:0] FLOAT = 'z
);
  localparam logic [6:0] PART = 7'b10x_0001;
  rand bit [7:0] x, z, part, sum;
  rand bit [7:0] wild;
  rand logic [7:0] lx;
  rand bit [7:0] p_wild, p_unknown, p_float, weighted, counted, w_part, w_unknown, bounded;
  rand int count_rand, count_state;
  bit [7:0] state;
  constraint c_bad {
    x == 8'bx;
    z == 'z;
    part != 8'b1x0;
    sum == x + 8'hx1;
    wild inside {8'b1???_????};
    lx == 'x;
    p_wild inside {WILD};
    p_unknown == UNKNOWN;
    p_float != FLOAT;
    weighted dist {1 := 'x, 2 := 1};
    count_rand == $countbits(counted, 1'bx);
    count_state == $countbits(state, 1'bz);
    w_part dist {7'd2 := PART};
    w_unknown dist {1 := UNKNOWN, 2 := 1};
    bounded dist {[WILD : 8'd250] := 1};
  }
endclass

class FourStateBounds;
  localparam logic [7:0] LOW_X = 8'b1x00_0000;
  localparam logic [7:0] HIGH_Z = 8'b1111_00zz;
  rand bit [7:0] d_high, d_value, i_low, i_high, i_low_lit, i_high_lit;
  constraint c_bounds {
    d_high dist {[8'd3 : HIGH_Z] :/ 1};
    d_value dist {8'b1z00_0000 := 1, 8'd3 := 1};
    i_low inside {[LOW_X : 8'd250]};
    i_high inside {[8'd3 : HIGH_Z]};
    i_low_lit inside {[8'b1x00_0000 : 8'd250]};
    i_high_lit inside {[8'd1 : 8'b1111_000z]};
  }
endclass

module t;
  initial begin
    FourState #() c;
    FourStateBounds b;
    c = new;
    void'(c.randomize());
    b = new;
    void'(b.randomize());
  end
endmodule
