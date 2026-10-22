// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

interface mem_if #(
    int unsigned ADDR_SIZE = 16
);
  logic [ADDR_SIZE-1:0] addr;
  modport mp(input addr);
endinterface

module t;
  class Cls #(
      type T = int
  );
  endclass

  // Note the referred-to virtual class is only used here, not instantiated
  typedef Cls#(virtual mem_if #(8)) cls_mem_if_t;
  typedef Cls#(virtual mem_if #()) cls_def_if_t;

  initial begin
    cls_mem_if_t c;
    cls_def_if_t d;
    c = new;
    d = new;
  end

  // Virtual interface variables of interfaces that are never instantiated
  class Holder;
    virtual mem_if #(3) v;
    virtual mem_if #(4).mp vm;
    virtual mem_if #(5) va[2];
    function bit isNull(virtual mem_if #(6) a);
      return a == null;
    endfunction
  endclass

  virtual mem_if #(7) v;
  virtual mem_if #(9).mp vm;
  virtual mem_if #(10) va[3];
  virtual mem_if #(11) vq[$];

  initial begin
    Holder h;
    virtual mem_if #(12) vl;
    h = new;
    `checkd(h.v == null, 1'b1);
    `checkd(h.vm == null, 1'b1);
    `checkd(h.va[1] == null, 1'b1);
    `checkd(h.isNull(null), 1'b1);
    `checkd(v == null, 1'b1);
    `checkd(vm == null, 1'b1);
    `checkd(va[2] == null, 1'b1);
    `checkd(vq.size(), 0);
    `checkd(vl == null, 1'b1);
    $write("*-* All Finished *-*\n");
    $finish;
  end

endmodule
