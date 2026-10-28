// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2023 Antmicro Ltd
// SPDX-License-Identifier: CC0-1.0

class Cls1;
endclass

class Cls2;
endclass

class ExtCls1;
endclass

interface class ICls1;
endclass

interface class ICls2;
endclass

module t;
  Cls1 c1;
  Cls2 c2;
  ExtCls1 ext_c1;
  ICls1 i1;
  ICls2 i2;

  initial begin
    c1 = (c1 != null) ? c1 : c2;
    c1 = (c1 != null) ? c2 : c2;
    c2 = (c1 == null) ? 1'b1 : c2;
    ext_c1 = (c1 == null) ? ext_c1 : c1;
    i1 = (c1 == null) ? i1 : i2;
  end
endmodule
