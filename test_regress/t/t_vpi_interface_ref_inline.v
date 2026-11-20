// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Interface references of a module with many instances. Each instance of
// Holder declares its own interfaces, which reach Leaf through a port of Mid.

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

// Public, so an instance named a C++ keyword is renamed
interface PubIntf;

  // verilator lint_off UNOPTPUBLIC
  logic [6:0] pub_intf_var  /* verilator public */;
  // verilator lint_on UNOPTPUBLIC

endinterface

module PubSink (
    PubIntf pub_ref
);

  logic [6:0] sink_saw;

  always_comb sink_saw = pub_ref.pub_intf_var;

endmodule

module Keep;
  /* verilator no_inline_module */

  // verilator lint_off SYMRSVDWORD
  PubIntf friend ();
  // verilator lint_on SYMRSVDWORD

  PubSink sink (.pub_ref(friend));

endmodule

module Pair;

  Holder h0 ();
  Holder h1 ();

endmodule

module t;

  Pair p0 ();
  Pair p1 ();
  Keep k ();

  initial begin
`ifdef VERILATOR
    $c("Verilated::scopesDump();");
`endif
    $write("*-* All Finished *-*\n");
    $finish;
  end

endmodule
