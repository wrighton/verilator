// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2025 Antmicro
// SPDX-License-Identifier: CC0-1.0

class Packet;
  rand real x;
  constraint cons { x + 1.0 > 0.0; }
endclass

class Elem;
  rand bit [3:0] y;
endclass

class DisableRandIndex;
  rand bit idx;
  rand Elem elems[2];
  constraint c_soft {
    soft elems[0].y == 4'h5;
    soft elems[1].y == 4'h6;
  }
  constraint c_disable { disable soft elems[idx].y; }
  function new();
    foreach (elems[i]) elems[i] = new;
  endfunction
endclass

typedef struct {
  rand Elem h;
} holder_t;

class DisableStructHandle;
  rand holder_t holders[2];
  constraint c_disable { disable soft holders[1].h.y; }
  function new();
    foreach (holders[i]) holders[i].h = new;
  endfunction
endclass

module t;
  Packet p;
  DisableRandIndex d;
  DisableStructHandle s;

  initial begin
    p = new;
    void'(p.randomize());
    d = new;
    void'(d.randomize());
    s = new;
    void'(s.randomize());
  end
endmodule
