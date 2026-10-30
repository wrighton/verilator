// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Antmicro
// SPDX-License-Identifier: CC0-1.0

typedef struct {
  int a;
  int b;
} us_t;

class Obj;
endclass

class C;
  rand int idx;
  us_t us[] = '{'{1, 2}, '{3, 4}};
  Obj objs[2];
  int unsigned m[3][2];
endclass

module t;
  C c;
  initial begin
    c = new;
    void'(c.randomize() with {us[idx].a == 3;});
    void'(c.randomize() with {objs[idx] == null;});
    void'(c.randomize() with {m[idx][1] > 0;});
  end
endmodule
