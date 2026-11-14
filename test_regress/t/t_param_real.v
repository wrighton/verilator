// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2015 Johan Bjork
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0x exp=%0x (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

module mod #(
    parameter real HZ = 0
);
  //verilator no_inline_module
  initial begin
    if ((HZ - $floor(HZ)) - 0.45 > 0.01) $stop;
    if ((HZ - $floor(HZ)) - 0.45 < -0.01) $stop;
  end
endmodule

module near_mod #(
    parameter real ZERO = 0.0,
    parameter real TINY = 1.0e-18,
    parameter real ONE = 1.0,
    parameter real BIG = 1.0e300,
    parameter real NEG = real'(-2.0)
);
endmodule

module t;
  mod #(.HZ(123.45)) mod1 ();
  mod #(.HZ(24.45)) mod2 ();

  // Overrides differing only slightly from their defaults, each alone, as an instance also
  // overriding another parameter gets all its values
  near_mod #(.ZERO(1.0e-20)) zero_pos ();
  near_mod #(.ZERO(-3.0e-300)) zero_neg ();
  near_mod #(.TINY(2.0e-18)) tiny_pos ();
  near_mod #(.TINY(-1.0e-18)) tiny_neg ();
  near_mod #(.ONE(1.0000000000000002)) one_ulp ();
  near_mod #(.BIG(1.0000000000000002e300)) big_ulp ();
  near_mod #(.NEG(-2.0000000000000004)) neg_ulp ();
  initial begin
    `checkh($realtobits(zero_pos.ZERO), $realtobits(1.0e-20));
    `checkh($realtobits(zero_neg.ZERO), $realtobits(-3.0e-300));
    `checkh($realtobits(tiny_pos.TINY), $realtobits(2.0e-18));
    `checkh($realtobits(tiny_neg.TINY), $realtobits(-1.0e-18));
    `checkh($realtobits(one_ulp.ONE), $realtobits(1.0000000000000002));
    `checkh($realtobits(big_ulp.BIG), $realtobits(1.0000000000000002e300));
    `checkh($realtobits(neg_ulp.NEG), $realtobits(-2.0000000000000004));
    if (mod1.HZ != 123.45) $stop;
    if (mod2.HZ != 24.45) $stop;
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
