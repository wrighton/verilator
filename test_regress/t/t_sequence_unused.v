// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2025 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

interface apb_if (
    input bit clk
);
  wire [31:0] paddr;
  wire [31:0] prdata;

  clocking mck @(posedge clk);
    output paddr;
    input prdata;

    // Some UVM tests declare this sequence but never use it
    // so we defer UNSUPPORTED until usage point
    sequence at_posedge;
      1;
    endsequence : at_posedge
  endclocking

endinterface

// Sequence library where no sequence is used by an assertion
package seq_lib;
  sequence eventually_true(e);
    (!e) [*0:$] ##1 e;
  endsequence
  sequence e1_not_before_e2(e1, e2);
    (!e1) throughout eventually_true(e2);
  endsequence
endpackage

module t (
    input clk
);

  apb_if ifc (clk);

  // Sequences instanced only by declarations that are not used (IEEE 1800-2023 16.8)
  logic a = 0, b = 1;
  sequence s_ab(x, y);
    x ##1 y;
  endsequence
  property p_unused(x, y);
    x |-> s_ab(y, y);
  endproperty
  sequence s_inner;
    a ##1 b;
  endsequence
  sequence s_unused;
    s_inner ##1 a;
  endsequence
  property p_restrict;
    s_inner;
  endproperty
  restrict property (p_restrict);

  initial $finish;

endmodule
