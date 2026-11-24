// DESCRIPTION: Verilator: virtual interface handle change in a sensitivity list
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

interface trigger_lane;
  logic sig;
endinterface

module t;
  trigger_lane a ();
  trigger_lane b ();
  virtual trigger_lane vh;
  int changes = 0;
  always @(vh) ++changes;

  initial begin
    #1;
    vh = a;
    #1;
    if (changes != 1) $fatal(1, "First handle change");
    a.sig = 1;
    #1;
    if (changes != 1) $fatal(1, "A member change is not a handle change");
    vh = b;
    #1;
    if (changes != 2) $fatal(1, "Second handle change");
    vh = null;
    #1;
    if (changes != 3) $fatal(1, "Null handle change");
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
