// DESCRIPTION: Verilator: Verilog Test module
//
// This program is free software; you can redistribute it and/or modify it
// under the terms of either the GNU Lesser General Public License Version 3
// or the Perl Artistic License Version 2.0.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: LGPL-3.0-only OR Artistic-2.0

// Interface references of a module instantiated many times through inlined
// levels. Each instance of Holder declares its own interfaces, which reach
// Leaf through a port of Mid.

interface SomeIntf;

  logic [6:0] some_intf_var;

  modport SomeModport(input some_intf_var);

endinterface

module Leaf (
    SomeIntf.SomeModport intf_ref
);

  logic [6:0] leaf_saw;

  always_comb leaf_saw = intf_ref.some_intf_var;

endmodule

module Mid (
    SomeIntf plain_ref
);

  Leaf leaf (.intf_ref(plain_ref));

endmodule

module Holder;

  SomeIntf concrete_intf ();

  Mid mid (.plain_ref(concrete_intf));

  // Declared in a named block
  if (1) begin : gen
    SomeIntf block_intf ();
    Mid mid (.plain_ref(block_intf));
  end

endmodule

module Pair;

  Holder h0 ();
  Holder h1 ();

endmodule

module t;

  Pair p0 ();
  Pair p1 ();

  initial begin
    $c("Verilated::scopesDump();");
    $write("*-* All Finished *-*\n");
    $finish;
  end

endmodule
