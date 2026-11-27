// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Variables each tied to a random value that conflicts alone come out spread over their
// values, though a solver names many of the ties in each unsat core (cvc5 most of them)

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define check_range(gotv,minv,maxv) do if ((gotv) < (minv) || (gotv) > (maxv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d-%0d\n", `__FILE__,`__LINE__, (gotv), (minv), (maxv)); `stop; end while(0);
// verilog_format: on

// A variable of 3 bits whose two low bits are equal: 0, 3, 4 or 7
`define C(i) \
  rand bit [2:0] c``i; \
  constraint k``i {c``i[0] == c``i[1];}

class Many;
  `C(0) `C(1) `C(2) `C(3) `C(4) `C(5) `C(6) `C(7) `C(8) `C(9) `C(10) `C(11) `C(12) `C(13) `C(14)
  `C(15) `C(16) `C(17) `C(18) `C(19) `C(20) `C(21) `C(22) `C(23) `C(24) `C(25) `C(26) `C(27)
  `C(28) `C(29) `C(30) `C(31) `C(32) `C(33) `C(34) `C(35) `C(36) `C(37) `C(38) `C(39) `C(40)
  `C(41) `C(42) `C(43) `C(44) `C(45) `C(46) `C(47) `C(48) `C(49) `C(50) `C(51) `C(52) `C(53)
  `C(54) `C(55) `C(56) `C(57) `C(58) `C(59) `C(60) `C(61) `C(62) `C(63)
  rand bit [3:0] g;
  // Keeps the solve off the sampler of small spaces, so each call spreads
  constraint c_g {soft g == 4'd3;}
endclass

`define COUNT(i) \
  `checkd(m.c``i[0], m.c``i[1]); \
  ++counts[m.c``i];

module t;
  initial begin
    automatic Many m = new;
    automatic int counts[8] = '{0, 0, 0, 0, 0, 0, 0, 0};
    automatic int ok;
    automatic bit cut = $test$plusargs("cut");
    m.srandom(1);
    repeat (5) begin
      ok = m.randomize();
      `checkd(ok, 1);
      `checkd(m.g, 4'd3);
      `COUNT(0) `COUNT(1) `COUNT(2) `COUNT(3) `COUNT(4) `COUNT(5) `COUNT(6) `COUNT(7) `COUNT(8)
      `COUNT(9) `COUNT(10) `COUNT(11) `COUNT(12) `COUNT(13) `COUNT(14) `COUNT(15) `COUNT(16)
      `COUNT(17) `COUNT(18) `COUNT(19) `COUNT(20) `COUNT(21) `COUNT(22) `COUNT(23) `COUNT(24)
      `COUNT(25) `COUNT(26) `COUNT(27) `COUNT(28) `COUNT(29) `COUNT(30) `COUNT(31) `COUNT(32)
      `COUNT(33) `COUNT(34) `COUNT(35) `COUNT(36) `COUNT(37) `COUNT(38) `COUNT(39) `COUNT(40)
      `COUNT(41) `COUNT(42) `COUNT(43) `COUNT(44) `COUNT(45) `COUNT(46) `COUNT(47) `COUNT(48)
      `COUNT(49) `COUNT(50) `COUNT(51) `COUNT(52) `COUNT(53) `COUNT(54) `COUNT(55) `COUNT(56)
      `COUNT(57) `COUNT(58) `COUNT(59) `COUNT(60) `COUNT(61) `COUNT(62) `COUNT(63)
    end
    // 80 each expected of 320, but when the spreading of the first call is cut short
    if (!cut) begin
      `check_range(counts[0], 50, 110);
      `check_range(counts[3], 50, 110);
      `check_range(counts[4], 50, 110);
      `check_range(counts[7], 50, 110);
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
