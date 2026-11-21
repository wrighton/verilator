// DESCRIPTION: Verilator: Verilog Test module for SystemVerilog 'alias'
//
// Alias width check error test.
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2025 Antmicro
// SPDX-License-Identifier: CC0-1.0

module t (  /*AUTOARG*/
    // Inputs
    clk
);
  input clk;

  logic [31:0] a;
  logic [31:0] b;

  alias a = b;

  logic [3:0] r;
  sub s (
      .o(),
      .r(r)
  );

endmodule

module sub (
    output logic [3:0] o,  // Variable, as explicitly data typed (IEEE 1800-2023 23.2.2.3)
    ref logic [3:0] r
);
  wire [3:0] w;
  wire [3:0] v;
  alias o = w;
  alias r = v;
endmodule
