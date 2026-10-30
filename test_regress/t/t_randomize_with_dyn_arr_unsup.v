// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Antmicro
// SPDX-License-Identifier: CC0-1.0

class Obj;
endclass

class C;
  rand int idx;
  Obj objs[2];
  Obj qobjs[$];
endclass

module t;
  C c;
  initial begin
    c = new;
    void'(c.randomize() with {objs[idx] == null;});
    void'(c.randomize() with {qobjs[idx] == null;});
  end
endmodule
