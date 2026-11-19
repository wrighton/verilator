// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Parameter overrides of a class reached through a class-type parameter, which the class does not
// have. As for any parameter override, Verilator drops one naming nothing once PINNOTFOUND is
// waived, and drops an empty '#()' silently.

class Outer #(
    int N = 4
);
  class Inner #(
      int M = 1,
      int P = 2
  );
    static function int f();
      return N * 100 + M * 10 + P;
    endfunction
  endclass
endclass

class OtherVal;
  class Inner #(
      int P = 9
  );
    static function int f();
      return P * 3;
    endfunction
  endclass
endclass

class OtherNoParam;
  class Inner;
    static function int f();
      return 5;
    endfunction
  endclass
endclass

class User #(
    type C = Outer#(2)
);
  static function int missing();
    // verilator lint_off PINNOTFOUND
    return C::Inner#(
        .M(7),
        .P(4)
    )::f();
    // verilator lint_on PINNOTFOUND
  endfunction
  static function int empty();
    return C::Inner#()::f();
  endfunction
endclass

module t;
  initial begin
    `checkd(User#()::missing(), 274);
    `checkd(User#(OtherVal)::missing(), 12);
    `checkd(User#(OtherNoParam)::empty(), 5);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
