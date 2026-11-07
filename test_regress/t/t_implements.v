// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2023 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

interface class Icempty;
endclass : Icempty

interface class Icls1;
  localparam LP1 = 1;
  pure virtual function int icf1;
  pure virtual function int icfboth;
  pure virtual function int icfpartial;
endclass

interface class Iext1 extends Icls1;
  pure virtual function int icf101;
endclass

interface class Icls2;
  pure virtual function int icf2(int in);
  pure virtual function int icfboth;
endclass

virtual class Base implements Iext1, Icls2;
  virtual function int icf1;
    return 1;
  endfunction
  virtual function int icf101;
    return 101;
  endfunction
  virtual function int icf2(int in);
    return in + 2;
  endfunction
  virtual function int icfboth;
    return 3;
  endfunction
  pure virtual function int icfpartial;
endclass

class Cls extends Base;
  virtual function int icfpartial;
    return 62;
  endfunction
endclass

interface class Icls3;
  localparam LP3 = 3;
  pure virtual function int icf3;
endclass

// Icls1 is also reached through Iext1
interface class Iext12 extends Iext1, Icls2, Icls1, Icls3;
  pure virtual function int icfboth;
endclass

class Cls12 implements Iext12;
  virtual function int icf101;
    return 111;
  endfunction
  virtual function int icf3;
    return 33;
  endfunction
  virtual function int icf1;
    return 11;
  endfunction
  virtual function int icf2(int in);
    return in + 12;
  endfunction
  virtual function int icfboth;
    return 13;
  endfunction
  virtual function int icfpartial;
    return 14;
  endfunction
endclass

module t;

  Cls c;
  Iext1 i1;
  Cls12 c12;
  Iext12 i12;

  initial begin
    if (Icls1::LP1 != 1) $stop;

    c = new;
    if (c.icf1() != 1) $stop;
    if (c.icf101() != 101) $stop;
    if (c.icf2(1000) != 1002) $stop;
    if (c.icfpartial() != 62) $stop;

    i1 = c;
    if (i1.icf1() != 1) $stop;
    if (i1.icf101() != 101) $stop;

    // Issue #9016: $cast to an interface class handle
    begin
      Icls2 i2;
      Cls c2;
      // verilator lint_off CASTCONST
      if ($cast(i2, c) != 1) $stop;
      if (i2.icf2(5) != 7) $stop;
      if ($cast(i1, c) != 1) $stop;
      // verilator lint_on CASTCONST
      if ($cast(c2, i1) != 1) $stop;
      if (c2 != c) $stop;
      // Unrelated interface class, checked at runtime
      i1 = c;
      if ($cast(i2, i1) != 1) $stop;
      if (i2.icf2(6) != 8) $stop;
      // Interface class handle to a class, and a cast that fails at runtime
      begin
        Base b;
        Icempty ie;
        if ($cast(b, i2) != 1) $stop;
        if (b != c) $stop;
        if ($cast(ie, i2) != 0) $stop;
        if (ie != null) $stop;
      end
    end

    // Methods inherited from every extended interface class
    c12 = new;
    i12 = c12;
    if (i12.icf1() != 11) $stop;
    if (i12.icf2(1000) != 1012) $stop;
    if (i12.icfboth() != 13) $stop;
    if (i12.icf101() != 111) $stop;
    if (i12.icf3 != 33) $stop;
    if (i12.LP3 != 3) $stop;

    $write("*-* All Finished *-*\n");
    $finish;
  end

endmodule
