// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module sub (
    input logic [15:0] in,
    output string out
);
  assign out = "ab";
endmodule

module t;
  typedef enum {A, B} enum_t;
  typedef string str_t;
  localparam string S = "ab";
  string s;
  str_t ts;
  int i;
  byte b;
  logic [15:0] v;
  logic [15:0] w;
  enum_t e;
  bit c;

  function automatic int f_in(int x);
    return x;
  endfunction
  task automatic t_out(output string o);
    o = "ab";
  endtask
  task automatic t_inout(inout string o);
    o = "ab";
  endtask

  // Illegal 'in' and 'out'
  sub u (
      .in(s),
      .out(w)
  );

  assign v = s;  // Illegal

  initial begin
    // Illegal: a string converts to an integral type only by a cast
    i = s;
    i = S;
    i = ts;
    b = s;
    e = s;
    v = $sformatf("%0d", i);
    i = c ? s : 5;
    i = f_in(s);
    t_out(i);
    t_inout(i);
    // Legal
    i = int'(s);
    i = s.atoi();
    i = "ab";
    b = s[0];
    s = i;
  end
endmodule
