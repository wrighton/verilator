// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Bit-stream casts to string from unpacked types (IEEE 1800-2023 6.24.3)

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define checks(gotv,expv) do if ((gotv) != (expv)) begin $write("%%Error: %s:%0d:  got='%s' exp='%s'\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module t (
    input clk
);
  typedef string str_t;
  typedef struct {
    logic [7:0] a;
    logic [7:0] b;
  } us_t;
  typedef struct {
    us_t s;
    logic [7:0] c;
  } nest_t;

  int cyc = 0;
  us_t us;
  nest_t ns;
  logic [7:0] ua[2];
  logic [7:0] uad[2:1];
  logic [7:0] ua2[2][2];
  logic [7:0] b9[9];
  logic [15:0] v;
  int calls = 0;
  string str;

  function automatic string getStr();
    return str;
  endfunction

  function automatic us_t getUs();
    ++calls;
    return us;
  endfunction

  always @(posedge clk) begin
    cyc <= cyc + 1;
    if (cyc == 0) begin
      us <= '{"A" + cyc[7:0], "B"};
      ns <= '{'{"A", "B"}, "K" + cyc[7:0]};
      ua <= '{"C" + cyc[7:0], "D"};
      uad[2] <= "E" + cyc[7:0];
      uad[1] <= "F";
      ua2 <= '{'{"G" + cyc[7:0], "H"}, '{"I", "J"}};
      v <= {"L" + cyc[7:0], "M"};
      for (int i = 0; i < 9; ++i) b9[i] <= "a" + cyc[7:0] + 8'(i);
      str <= $sformatf("N%0d", cyc);
    end
    else if (cyc == 1) begin
      `checks(string'(us), "AB");
      `checks(str_t'(us), "AB");
      `checks(string'(ns), "ABK");
      `checks(string'(ua), "CD");
      `checks(str_t'(ua), "CD");
      `checks(string'(uad), "EF");
      `checks(string'(ua2), "GHIJ");
      `checks(string'(b9), "abcdefghi");
      `checks({string'(ua), "x"}, "CDx");
      `checks(string'({>>{v}}), "LM");
      `checks(string'({<<8{v}}), "ML");
      `checks(string'(getUs()), "AB");
      `checkd(calls, 1);
      // Of a string
      `checks(string'(str), "N0");
      `checks(str_t'(str), "N0");
      `checks(string'(getStr()), "N0");
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
