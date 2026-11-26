// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

// Before enough clock ticks, $past returns the default sampled value of its expression (IEEE
// 1800-2023 16.9.3), which for a nested $past is the default sampled value of the inner expression
// (IEEE 1800-2023 16.5.1)
module t;
  typedef struct packed {
    bit [2:0] a;
    bit [3:0] b;
  } s_t;

  bit clk = 0;
  // Default sampled values 61, 1 and {5, 9}, the declaration initializers; then other values from
  // time 0, changing between clock ticks
  bit [6:0] x = 61;
  bit b = 1;
  s_t s = '{a: 3'd5, b: 4'd9};
  initial begin
    x = 7;
    b = 0;
    s = '{a: 3'd1, b: 4'd2};
    repeat (8) begin
      #5 clk = 1;
      #5 clk = 0;
      x = x + 7'd3;
      b = !b;
      s.a = s.a + 3'd3;
      s.b = s.b + 4'd1;
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end

  // Sampled values at each clock tick k
  int k = 0;
  bit [6:0] xh[0:7];
  bit bh[0:7];
  s_t sh[0:7];
  function automatic bit [6:0] xPast(int n);
    return k >= n ? xh[k-n] : 7'd61;
  endfunction
  function automatic bit bPast(int n);
    return k >= n ? bh[k-n] : 1'b1;
  endfunction
  function automatic s_t sPast(int n);
    return k >= n ? sh[k-n] : s_t'{a: 3'd5, b: 4'd9};
  endfunction

  always @(posedge clk) begin
    xh[k] = x;
    bh[k] = b;
    sh[k] = s;
    // Test: nesting of two and three levels
    `checkd($past($past(x)), xPast(2));
    `checkd($past($past($past(x))), xPast(3));
    // Test: more than one tick, outer and inner
    `checkd($past($past(x), 2), xPast(3));
    `checkd($past($past(x, 3)), xPast(4));
    `checkd($past($past(x, 2), 3), xPast(5));
    // Test: nested in value change functions
    `checkd($stable($past(x)), xPast(1) == (k >= 1 ? xPast(2) : 7'd61));
    `checkd($changed($past(x)), xPast(1) != (k >= 1 ? xPast(2) : 7'd61));
    `checkd($rose($past(b)), bPast(1) && !(k >= 1 ? bPast(2) : 1'b1));
    `checkd($fell($past(b)), !bPast(1) && (k >= 1 ? bPast(2) : 1'b1));
    // Test: structure operand, and an expression of a member
    `checkd($past($past(s)), sPast(2));
    `checkd($past($past(s.a) + 3'd1), (k >= 1 ? sPast(2).a : 3'd5) + 3'd1);
    k = k + 1;
  end
endmodule
