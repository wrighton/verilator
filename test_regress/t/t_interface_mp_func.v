// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2014 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

function automatic int get_val(const ref int x);
  return x;
endfunction

class Obj;
  int v;
endclass

class Setter;
  function void set(output int o);
    o = 5;
  endfunction
endclass

typedef Obj obj_alias_t;
typedef struct {obj_alias_t h;} holder_t;

interface pads_if ();
  modport mp_dig(import fIn, import fOut);
  modport mp_rd(input exists, input aa, input h, input harr, input hs);

  int aa[int];
  Obj h;
  Obj harr[2];
  holder_t hs;

  integer exists[8];
  function automatic integer fIn(integer i);
    fIn = exists[i];
  endfunction
  task automatic fOut(integer i);
    exists[i] = 33;
  endtask
endinterface

module rd_elem (
    pads_if.mp_rd p
);
  // Element of an array through an input-only modport is read, not created
  function automatic int get_rd(input int k);
    return get_val(p.aa[k]);
  endfunction
  // A member of the object an input-only handle refers to can be written
  function automatic void set_h_v();
    Setter s = new;
    s.set(p.h.v);
    s.set(p.harr[1].v);
    s.set(p.hs.h.v);
  endfunction
endmodule

module t;
  pads_if padsif[1:0] ();
  pads_if padsif_arr[1:0] ();
  rd_elem rd_i (.p(padsif[0]));
  virtual pads_if.mp_rd vrd;
  initial begin
    padsif[0].fOut(3);
    if (padsif[0].fIn(3) != 33) $stop;

    padsif_arr[0].fOut(3);
    if (padsif_arr[0].fIn(3) != 33) $stop;
    padsif_arr[1].fOut(3);
    if (padsif_arr[1].fIn(3) != 33) $stop;
    `checkd(rd_i.get_rd(7), 0);
    `checkd(padsif[0].aa.exists(7), 0);
    // Also through a virtual interface
    vrd = padsif[0];
    `checkd(get_val(vrd.aa[9]), 0);
    `checkd(padsif[0].aa.exists(9), 0);
    `checkd(get_val(padsif[1].aa[8]), 0);
    `checkd(padsif[1].aa.exists(8), 1);
    padsif[0].h = new;
    padsif[0].harr[1] = new;
    padsif[0].hs.h = new;
    rd_i.set_h_v();
    `checkd(padsif[0].h.v, 5);
    `checkd(padsif[0].harr[1].v, 5);
    `checkd(padsif[0].hs.h.v, 5);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
