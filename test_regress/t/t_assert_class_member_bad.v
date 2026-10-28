// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

class C;
  bit x = 1'b1;
  static bit sx = 1'b1;
  localparam bit P = 1'b1;
  function bit get();
    return x;
  endfunction
  static function bit sget();
    return sx;
  endfunction
  function void check();
    // OK: immediate assertion in a method
    assert (x);
  endfunction
endclass

module t (
    input clk
);
  C o = new;

  sequence s_member;
    o.x ##1 1'b1;
  endsequence

  // Bad: non-static property and method
  a_x :
  assert property (@(posedge clk) o.x);
  a_get :
  assert property (@(posedge clk) o.get());
  a_seq :
  cover property (@(posedge clk) s_member);
  // OK: static property and method, and parameter, through a handle
  a_sx :
  assert property (@(posedge clk) o.sx && o.sget() && o.P);
  // OK: not a concurrent assertion
  always @(posedge clk) begin
    assert (o.x && o.get());
    o.check();
  end
endmodule
