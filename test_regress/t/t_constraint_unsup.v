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
  rand Elem dynElems[];
  constraint c_soft {
    soft elems[0].y == 4'h5;
    soft elems[1].y == 4'h6;
    soft dynElems[idx].y == 4'h7;
  }
  constraint c_disable {
    disable soft elems[idx].y;
    disable soft dynElems[idx].y;
  }
  function new();
    foreach (elems[i]) elems[i] = new;
    dynElems = new[2];
    foreach (dynElems[i]) dynElems[i] = new;
  endfunction
endclass

typedef struct {
  rand Elem h;
} holder_t;

class DisableStructHandle;
  rand holder_t holder;
  rand holder_t holders[2];
  constraint c_disable {
    disable soft holder.h.y;
    disable soft holders[1].h.y;
  }
  function new();
    holder.h = new;
    foreach (holders[i]) holders[i].h = new;
  endfunction
endclass

class RandIndexElem;
  rand bit [6:0] v;
endclass

class RandIndexObject;
  rand RandIndexElem items[3];
  rand RandIndexElem ditems[];
  rand RandIndexElem qitems[$];
  rand RandIndexElem rows[$][2];
  rand int unsigned k;
  constraint c_index {
    k < 3;
    items[k].v == 7'd5;
    ditems[k].v == 7'd6;
    qitems[k].v == 7'd7;
    rows[k][0].v == 7'd8;
  }
  function new();
    foreach (items[i]) items[i] = new;
    ditems = new[3];
    foreach (ditems[i]) ditems[i] = new;
    repeat (3) qitems.push_back(null);
    foreach (qitems[i]) qitems[i] = new;
    rows = '{'{null, null}, '{null, null}};
    foreach (rows[i, j]) rows[i][j] = new;
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
    begin
      automatic RandIndexObject o = new;
      void'(o.randomize());
    end
  end
endmodule
