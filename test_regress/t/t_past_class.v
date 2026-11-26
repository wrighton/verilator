// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Sampled value functions with a clocking event argument, in a class outside the module
class D;
  static int v = 3;
  static function int past1();
    return $past(v, 1,, @(posedge t.clk));
  endfunction
  static function bit stable();
    return $stable(v, @(posedge t.clk));
  endfunction
endclass

module t (
    input clk
);

  default clocking @(posedge clk);
  endclocking

  // Sampled value functions of a static property in static methods, clocked by default clocking
  class C;
    static int v = 5;
    static function int past1();
      return $past(v);
    endfunction
    static function int past2();
      return $past(v, 2);
    endfunction
    static function bit stable();
      return $stable(v);
    endfunction
    static function bit rose();
      return $rose(v[0]);
    endfunction
  endclass

  int cyc = 0;
  int h1 = 5;  // 'v' sampled at the previous edge
  int h2 = 5;  // 'v' sampled at the edge before
  int d1 = 3;  // 'D::v' sampled at the previous edge
  always @(negedge clk) C::v <= C::v + cyc * 3 + 1;
  always @(negedge clk) D::v <= D::v + cyc % 2;
  always @(posedge clk) begin
    `checkd(C::past1(), h1);
    `checkd(C::past2(), h2);
    `checkd(C::stable(), C::v == h1);
    `checkd(C::rose(), C::v[0] && !h1[0]);
    `checkd(D::past1(), d1);
    `checkd(D::stable(), D::v == d1);
    h1 <= C::v;
    h2 <= h1;
    d1 <= D::v;
    cyc <= cyc + 1;
    if (cyc == 10) begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
