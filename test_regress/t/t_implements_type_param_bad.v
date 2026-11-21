// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

interface class Icls;
endclass

// Type parameters cannot be implemented or extended in these contexts,
// even when they resolve to interface classes (IEEE 1800-2023 8.26.4).
class Concrete #(type T = Icls) implements T;
endclass

virtual class Abstract #(type T = Icls) implements T;
endclass

interface class Derived #(type T = Icls) extends T;
endclass

module t;
  Concrete #(Icls) concrete;
  Abstract #(Icls) abstract_handle;
  Derived #(Icls) derived_handle;
endmodule
