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

  // Test: string literal to input arguments, copied by value like an assignment
  function automatic byte left_asc(byte a[0:2]);
    return a[0];
  endfunction
  function automatic byte right_desc(byte a[2:0]);
    return a[0];
  endfunction
  function automatic bit [31:0] pack_bounds(input byte a[5:2]);
    return {a[5], a[4], a[3], a[2]};
  endfunction
  function automatic bit [23:0] pack_typedef(bytes4_t a, u8_t b[1:3]);
    a[0] = "z";  // Changes only the copy
    return {b[1], b[2], b[3]};
  endfunction
  function automatic bit [15:0] pack_default(byte a[0:1] = "d");
    return {a[0], a[1]};
  endfunction
  task automatic get_task(input logic [7:0] a[3:1], output bit [23:0] o);
    o = {a[3], a[2], a[1]};
  endtask
  class Cls;
    static function bit [15:0] pack_static(byte a[1:2]);
      return {a[1], a[2]};
    endfunction
    function bit [15:0] pack_method(byte a[0:1]);
      return {a[0], a[1]};
    endfunction
  endclass

  // Constant function evaluation
  localparam bit [31:0] BOUNDS = pack_bounds("xy");

  task automatic check_arguments;
    bytes4_t ba = "copy";
    u8_t ub[1:3] = "var";
    bit [23:0] o;
    Cls c = new;
    `checkh(left_asc("ab"), "a");
    `checkh(right_desc("ab"), 8'h0);
    `checkh(right_desc("abcd"), "c");
    `checkh(right_desc("a"), 8'h0);
    `checkh(pack_bounds("wxyz"), "wxyz");
    `checkh(pack_bounds("wx"), {"wx", 16'h0});
    `checkh(pack_bounds("vwxyz"), "vwxy");
    `checkh(pack_bounds(""), 32'h0);
    `checkh(pack_bounds("\000\377\200"), 32'h00ff8000);
    `checkh(pack_typedef("abcd", "\200\377"), 24'h80ff00);
    `checkh(pack_typedef(ba, ub), "var");
    `checkh(ba[0], "c");
    `checkh(pack_default(), {"d", 8'h0});
    `checkh(pack_default(.a("ef")), "ef");
    get_task("lmn", o);
    `checkh(o, "lmn");
    get_task(.o(o), .a("pq"));
    `checkh(o, {"pq", 8'h0});
    `checkh(Cls::pack_static("s"), {"s", 8'h0});
    `checkh(c.pack_method("tuv"), "tu");
    `checkh(BOUNDS, {"xy", 16'h0});
  endtask

  // Check in one process, as initial procedures run in an unspecified order
  initial begin
    check_left_justified();
    check_sizes();
    check_characters();
    check_empty();
    check_automatic();
    check_arguments();
    $write("*-* All Finished *-*\n");
    $finish;
  end

endmodule
