// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t (
    input clk
);
  logic a, b, c, d;
  bit qq[$];
  int n;
  class Cls;
    static bit s;
  endclass
  Cls obj = new;
  function automatic bit g(bit x);
    return x;
  endfunction
  task automatic tk(input bit v);
    cover property (@(posedge clk) v within (b ##1 !b[+] ##1 b));
  endtask
  function automatic bit f();
    n++;
    return n[0];
  endfunction

  // The bounded repetition would need too many states
  cover property (@(posedge clk) a within (b ##1 !b[*1:6000] ##1 b));

  // A variable-length outer sequence is only supported as a repetition of a
  // pure boolean, between ticks requiring its negation, as the whole sequence
  // of a cover property
  cover property (@(posedge clk) a within (b ##[1:3] c));
  cover property (@(posedge clk) a within (b ##1 c[+] ##1 d));
  cover property (@(posedge clk) a within (b ##1 !b[+]));
  cover property (@(posedge clk) a within ((b || c) ##1 !b[+] ##1 b));
  cover property (@(posedge clk) a within ((b ##1 c) ##1 !b[+] ##1 b));
  cover property (@(posedge clk) a within (b ##1 !b[+] ##1 (c ##1 b)));
  cover property (@(posedge clk) a within (f() ##1 !f()[+] ##1 f()));
  cover property (@(posedge clk) f() within (b ##1 !b[+] ##1 b));
  cover property (@(posedge clk) a within (g(b) ##1 !g(b)[+] ##1 g(b)));
  cover property (@(posedge clk) (qq.size() > 0) within (b ##1 !b[+] ##1 b));
  cover property (@(posedge clk) a within (Cls::s ##1 !Cls::s[+] ##1 Cls::s));
  cover property (@(posedge clk) a within (obj.s ##1 !obj.s[+] ##1 obj.s));
  cover property (@(posedge clk) a within ((obj != null) ##1 !(obj != null)[+] ##1 (obj != null)));
  cover property (@(posedge clk) a within (b ##1 !b[+] ##1 (##1 b)));
  cover property (@(posedge clk) a within (b ##1 !b[+] ##1 b ##1 !b[+] ##1 b));
  cover property (@(posedge clk) (a within (b ##1 !b[+] ##1 b)) ##1 c);
  cover property (@(posedge clk) (a within (b ##1 !b[+] ##1 b)) |-> c);
  cover property (@(posedge clk) not (a within (b ##1 !b[+] ##1 b)));
  cover sequence (@(posedge clk) a within (b ##1 !b[+] ##1 b));
  assert property (@(posedge clk) a within (b ##1 !b[+] ##1 b));
  always @(posedge clk) cover property (a within (b ##1 !b[+] ##1 b));
  always @(posedge clk) begin
    automatic logic v = a;
    cover property (v within (b ##1 !b[+] ##1 b));
  end

  // verilog_format: off
  sequence s_event;
    @(posedge clk) a within (b ##1 !b[+] ##1 b);
  endsequence
  // verilog_format: on
  initial @s_event;

endmodule
