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

    begin
      // A string and a real are never cast compatible (IEEE 1800-2023 6.24.1), so $cast fails
      // and leaves the destination unchanged
      typedef real real_t;
      string s;
      real_t r;
      s = $sformatf("%0d.5", $time + 1);
      r = 2.5;
      i = -1;
      i = $cast(r, s);
      if (i != 0) $stop;
      if (r != 2.5) $stop;
      i = -1;
      i = $cast(s, r);
      if (i != 0) $stop;
      if (s != "1.5") $stop;
      void'($cast(s, r));
      if (s != "1.5") $stop;
    end

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
