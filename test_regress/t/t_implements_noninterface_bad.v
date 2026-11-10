// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2023 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

class NotIcls;
endclass

class ClsBad1 implements NotIcls;
endclass

interface class Icls;
endclass

class ClsBad2 extends Icls;
endclass

// An interface class may extend only interface classes (IEEE 1800-2023 8.26.2).
interface class BadPlain extends NotIcls;
endclass

typedef NotIcls NotIclsAlias;
interface class BadAlias extends NotIclsAlias;
endclass

interface class FnIcls;
  pure virtual function void f();
endclass

virtual class VirtualNotIcls;
  virtual function void f();
  endfunction
  pure constraint pc;
endclass

// The reported case: a virtual class provides a method and a pure constraint.
interface class BadVirtual extends VirtualNotIcls, FnIcls;
endclass

module t;
  ClsBad2 c;
endmodule
