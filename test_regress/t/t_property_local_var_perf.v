// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define N1(x) (a and x)
`define N2(x) `N1(`N1(x))
`define N4(x) `N2(`N2(x))
`define N8(x) `N4(`N4(x))
`define N16(x) `N8(`N8(x))
`define N32(x) `N16(`N16(x))
`define N64(x) `N32(`N32(x))
`define N128(x) `N64(`N64(x))
`define N256(x) `N128(`N128(x))
`define O1(x) (a or x)
`define O2(x) `O1(`O1(x))
`define O4(x) `O2(`O2(x))
`define O8(x) `O4(`O4(x))
`define O16(x) `O8(`O8(x))
`define O32(x) `O16(`O16(x))
`define D1(p) int p``0; int p``1;
`define S1(p) , p``0 = cyc, p``1 = cyc
`define D2(p) `D1(p``0) `D1(p``1)
`define D4(p) `D2(p``0) `D2(p``1)
`define D8(p) `D4(p``0) `D4(p``1)
`define D16(p) `D8(p``0) `D8(p``1)
`define D32(p) `D16(p``0) `D16(p``1)
`define D64(p) `D32(p``0) `D32(p``1)
`define D128(p) `D64(p``0) `D64(p``1)
`define S2(p) `S1(p``0) `S1(p``1)
`define S4(p) `S2(p``0) `S2(p``1)
`define S8(p) `S4(p``0) `S4(p``1)
`define S16(p) `S8(p``0) `S8(p``1)
`define S32(p) `S16(p``0) `S16(p``1)
`define S64(p) `S32(p``0) `S32(p``1)
`define S128(p) `S64(p``0) `S64(p``1)
// verilog_format: on

module t (
    input clk,
    input a,
    input int cyc
);
  // A local variable beside 400 nested composite sequence operators
  property p;
    int x;
    @(posedge clk) (1'b1, x = cyc) ##1 (cyc == x + 1) ##1 `N256(`N128(`N16(a)));
  endproperty
  assert property (p);
  // 400 local variables assigned inside 400 nested composite sequence operators
  property p_nested;
    `D128(u) `D64(v) `D8(w)
    @(posedge clk) `N256(`N128(`N16((1'b1 `S128(u) `S64(v) `S8(w))))) ##1 a;
  endproperty
  assert property (p_nested);
  // 100 local variables assigned inside, or before and inside, 100 nested 'intersect',
  // 'and' and 'or' operators
  property p_mixed_inner;
    `D32(u) `D16(v) `D2(w)
    @(posedge clk)
    `O32(`O16(`O1(`N32(`N16(`N2((a intersect (1'b1 `S32(u) `S16(v) `S2(w))))))))) ##1 a;
  endproperty
  assert property (p_mixed_inner);
  property p_mixed_before;
    `D32(u) `D16(v) `D2(w)
    @(posedge clk) (1'b1 `S32(u) `S16(v) `S2(w)) ##1
    `O32(`O16(`O1(`N32(`N16(`N2((a intersect (1'b1 `S32(u) `S16(v) `S2(w))))))))) ##1 a;
  endproperty
  assert property (p_mixed_before);
endmodule
