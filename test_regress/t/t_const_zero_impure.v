// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module t;

  int cnt = 0;
  function automatic logic [7:0] f();
    ++cnt;
    return 8'd3;
  endfunction

  function automatic logic fb();
    ++cnt;
    return 1'b1;
  endfunction

  typedef struct {logic b;} s_t;
  function automatic s_t fs();
    s_t s;
    ++cnt;
    s.b = 1'b1;
    return s;
  endfunction

  class Cls;
    logic b = 1'b1;
  endclass
  function automatic Cls fc();
    Cls c = new;
    ++cnt;
    return c;
  endfunction

  // Expressions with a zero operand that are constant regardless of another operand with
  // side effects, which must still be evaluated
  initial begin
    logic r;
    logic [7:0] u;
    logic signed [7:0] s;
    logic [69:0] w;
    logic [3:0] n;
    u = 8'd0 * f();
    `checkd(u, 8'd0);
    `checkd(cnt, 1);
    u = f() * 8'd0;
    `checkd(u, 8'd0);
    `checkd(cnt, 2);
    s = 8'sd0 * $signed(f());
    `checkd(s, 8'sd0);
    `checkd(cnt, 3);
    u = 8'd0 / f();
    `checkd(u, 8'd0);
    `checkd(cnt, 4);
    s = 8'sd0 / $signed(f());
    `checkd(s, 8'sd0);
    `checkd(cnt, 5);
    u = 8'd0 << f();
    `checkd(u, 8'd0);
    `checkd(cnt, 6);
    u = 8'd0 >> f();
    `checkd(u, 8'd0);
    `checkd(cnt, 7);
    s = 8'sd0 >>> f();
    `checkd(s, 8'sd0);
    `checkd(cnt, 8);
    u = 8'd0 & f();
    `checkd(u, 8'd0);
    `checkd(cnt, 9);
    u = f() & 8'd0;
    `checkd(u, 8'd0);
    `checkd(cnt, 10);
    u = 8'h0f & (f() << 4);
    `checkd(u, 8'd0);
    `checkd(cnt, 11);
    r = (f() != 8'd0) && 1'b0;
    `checkd(r, 1'b0);
    `checkd(cnt, 12);
    w = 70'd0 * {62'd0, f()};
    `checkd(w, 70'd0);
    `checkd(cnt, 13);
    r = fs().b && 1'b0;
    `checkd(r, 1'b0);
    `checkd(cnt, 14);
    r = fc().b && 1'b0;
    `checkd(r, 1'b0);
    `checkd(cnt, 15);
    // Selects of a concatenation, and powers, that discard an operand with side effects
    n = 4'({f(), 4'd5});
    `checkd(n, 4'd5);
    `checkd(cnt, 16);
    u = 8'({4'd5, f()} >> 8);
    `checkd(u, 8'd5);
    `checkd(cnt, 17);
    w = 70'({f(), 70'd7});
    `checkd(w, 70'd7);
    `checkd(cnt, 18);
    u = f() ** 8'd0;
    `checkd(u, 8'd1);
    `checkd(cnt, 19);
    // Comparisons with a constant out of the range of the other operand
    r = 9'(f()) == 9'h100;
    `checkd(r, 1'b0);
    `checkd(cnt, 20);
    r = 9'(f()) != 9'h100;
    `checkd(r, 1'b1);
    `checkd(cnt, 21);
    r = 9'(f()) < 9'h100;
    `checkd(r, 1'b1);
    `checkd(cnt, 22);
    r = 9'(f()) >= 9'h100;
    `checkd(r, 1'b0);
    `checkd(cnt, 23);
    r = 9'(f()) > 9'h100;
    `checkd(r, 1'b0);
    `checkd(cnt, 24);
    r = 9'(f()) <= 9'h100;
    `checkd(r, 1'b1);
    `checkd(cnt, 25);
    s = $signed(f()) ** 8'sd0;
    `checkd(s, 8'sd1);
    `checkd(cnt, 26);
    s = $signed(f()) ** 8'd0;
    `checkd(s, 8'sd1);
    `checkd(cnt, 27);
    u = f() ** 8'sd0;
    `checkd(u, 8'd1);
    `checkd(cnt, 28);
    // Reductions that are constant regardless of an operand with side effects
    r = &(9'(f()));
    `checkd(r, 1'b0);
    `checkd(cnt, 29);
    r = $onehot0(fb());
    `checkd(r, 1'b1);
    `checkd(cnt, 30);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
