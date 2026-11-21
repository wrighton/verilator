// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2022 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t (/*AUTOARG*/
  // Inputs
  rbad, rok
  );
  input real rbad;
  input real rok;
  event ebad;
  struct packed { int a; } sok;

  always @ (rok) $stop;
  always @ (sok) $stop;

  always @ (posedge rbad) $stop;
  always @ (posedge ebad) $stop;

  class Cls;
  endclass
  Cls cbad;
  always @ (cbad) $stop;  // Value change on a handle is legal
  always @ (posedge cbad) $stop;
  always @ (negedge cbad) $stop;
  always @ (edge cbad) $stop;

  logic uabad[2];
  always @ (posedge uabad) $stop;

endmodule
