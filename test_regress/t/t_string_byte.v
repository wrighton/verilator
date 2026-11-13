// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2022 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module t;

  // Unpacked byte from string IEEE 1800-2023 5.9: if the sizes differ, the string is left
  // justified, so the first character is in the left element
  byte bh[3:0] = "hi2";
  byte bl[0:3] = "lo2";

  task automatic check_left_justified;
    `checkh(bh[3], "h");
    `checkh(bh[2], "i");
    `checkh(bh[1], "2");
    `checkh(bh[0], 8'h0);
    `checkh(bl[0], "l");
    `checkh(bl[1], "o");
    `checkh(bl[2], "2");
    `checkh(bl[3], 8'h0);
  endtask

  // Test: equal and longer strings, non-zero bounds
  byte beq[2:5] = "abcd";
  byte blong[5:3] = "wxyz";

  task automatic check_sizes;
    `checkh(beq[2], "a");
    `checkh(beq[3], "b");
    `checkh(beq[4], "c");
    `checkh(beq[5], "d");
    `checkh(blong[5], "w");
    `checkh(blong[4], "x");
    `checkh(blong[3], "y");
  endtask

  // Test: embedded NUL and high characters, typedef array and element types, signedness
  typedef byte bytes4_t[4];
  typedef bit [7:0] u8_t;
  bytes4_t bnul = "a\000\377";
  u8_t uhigh[3:1] = "\200\377";

  task automatic check_characters;
    `checkh(bnul[0], "a");
    `checkh(bnul[1], 8'h0);
    `checkd(bnul[2], -1);
    `checkh(bnul[3], 8'h0);
    `checkd(uhigh[3], 128);
    `checkd(uhigh[2], 255);
    `checkd(uhigh[1], 0);
  endtask

  // Test: empty string
  byte bempty[1:3] = "";

  task automatic check_empty;
    `checkh(bempty[1], 8'h0);
    `checkh(bempty[2], 8'h0);
    `checkh(bempty[3], 8'h0);
  endtask

  // Test: automatic variables and procedural assignments
  task automatic check_automatic;
    byte la[1:4] = "xy";
    logic [7:0] ld[4:2];
    `checkh(la[1], "x");
    `checkh(la[2], "y");
    `checkh(la[3], 8'h0);
    `checkh(la[4], 8'h0);
    la = "pqrst";
    `checkh(la[1], "p");
    `checkh(la[2], "q");
    `checkh(la[3], "r");
    `checkh(la[4], "s");
    la = "z";
    `checkh(la[1], "z");
    `checkh(la[2], 8'h0);
    `checkh(la[3], 8'h0);
    `checkh(la[4], 8'h0);
    ld = "m\000";
    `checkh(ld[4], "m");
    `checkh(ld[3], 8'h0);
    `checkh(ld[2], 8'h0);
  endtask

  // Check in one process, as initial procedures run in an unspecified order
  initial begin
    check_left_justified();
    check_sizes();
    check_characters();
    check_empty();
    check_automatic();
    $write("*-* All Finished *-*\n");
    $finish;
  end

endmodule
