// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2020 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

class Base;
endclass
class BasedA extends Base;
endclass
class BasedB extends Base;
  static function BasedB getBasedB(bit getNull);
    BasedB b = new;
    return getNull ? null : b;
  endfunction
endclass
interface class Ia;
endclass
interface class Ib;
endclass
class Impl extends Base implements Ia, Ib;
endclass
class ImplA implements Ia;
endclass

module t;
  int i;
  int a;
  int ao;

  Base b;
  Base bo;
  BasedA ba;
  BasedA bao;
  BasedB bb;
  BasedB bbo;

  // verilator lint_off CASTCONST

  initial begin
    a = 1234;
    i = $cast(ao, a);
    if (i != 1) $stop;
    if (ao != 1234) $stop;

    a = 12345;
    $cast(ao, a);
    if (ao != 12345) $stop;

    i = $cast(ao, 2.1 * 3.7);
    if (i != 1) $stop;
    if (ao != 8) $stop;

    i = $cast(bo, null);
    if (i != 1) $stop;
    if (bo != null) $stop;

    ba = new;
    b = ba;
    i = $cast(bao, b);
    if (i != 1) $stop;
    if (b != ba) $stop;

    bb = new;
    b = bb;
    i = $cast(bbo, b);
    if (i != 1) $stop;
    if (b != bb) $stop;

    bb = null;
    b = bb;
    i = $cast(bbo, b);
    if (i != 1) $stop;
    if (b != bb) $stop;

    bb = BasedB::getBasedB(1);
    b = bb;
    i = $cast(bbo, b);
    if (i != 1) $stop;
    if (b != bb) $stop;

    bb = new;
    b = bb;
    bao = ba;
    i = $cast(bao, b);
    if (i != 0) $stop;
    if (bao != ba) $stop;  // Unchanged
    void'($cast(bao, b));  // Ok as is function

    // IEEE 1800-2023 8.26.5: Casts to or from interface classes are checked at runtime
    begin
      Impl impl;
      ImplA impla;
      Ia ia;
      Ib ib;
      impl = new;
      ib = Ib'(impl);  // Static upcast to second implemented interface class
      if (ib != impl) $stop;
      ib = null;
      i = $cast(ib, impl);
      if (i != 1) $stop;
      if (ib != impl) $stop;
      ia = impl;
      ib = null;
      i = $cast(ib, ia);  // Interface class to interface class
      if (i != 1) $stop;
      if (ib != impl) $stop;
      b = impl;
      ia = null;
      i = $cast(ia, b);  // Class to interface class implemented by derived class
      if (i != 1) $stop;
      if (ia != impl) $stop;
      bo = null;
      i = $cast(bo, ib);  // Interface class to class
      if (i != 1) $stop;
      if (bo != impl) $stop;
      impla = new;
      ia = impla;
      ib = null;
      i = $cast(ib, ia);
      if (i != 0) $stop;
      if (ib != null) $stop;
      b = bb;
      ia = null;
      i = $cast(ia, b);
      if (i != 0) $stop;
      bo = bb;
      i = $cast(bo, ia);  // Null source
      if (i != 1) $stop;
      if (bo != null) $stop;
    end

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
