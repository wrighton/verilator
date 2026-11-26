// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2025 Antmicro
// SPDX-License-Identifier: CC0-1.0

interface QBus (
    input logic k
);
  logic data;
  // Hierarchical references in an interface without instances are not elaborated
  function automatic void poke(logic v);
    missing_inst.mem[0] = v;
  endfunction
  function automatic void poke_indexed(logic v);
    missing_insts[0].mem = v;
  endfunction
  function automatic int peek();
    int other_local;
    other_local = 1;
    return other_local;
  endfunction
  // Named as a variable of another function only
  function automatic void poke_other(logic v);
    other_local.mem = v;
  endfunction
  // Named as a variable of a nested block only
  function automatic void poke_block(logic v);
    begin
      int block_local;
      block_local = 1;
    end
    block_local.mem = v;
  endfunction
  task automatic drive(virtual QBus other);
    other.data = 1;
  endtask
  task automatic fork_named();
    fork
      begin : fork_blk
        static int fx = 1;
        fx = missing_inst.fz;
      end
    join
  endtask
  task automatic call_missing();
    missing_inst.go();
  endtask
  // Named in another branch of a fork only
  task automatic fork_other();
    fork
      begin
        int branch_local;
        branch_local = 1;
      end
      begin
        branch_local.mem = 1;
      end
    join
  endtask
  always @(data) missing_inst.copy = data;
  // Names in blocks of such code stay declared
  initial begin : blk
    static int x = 1;
    x = missing_inst.y;
  end
  int y2;
  initial y2 = blk.x;
  always @(data) begin : ablk
    static int ax = 2;
    ax = missing_inst.ay;
  end
  function automatic int get_ax();
    return ablk.ax;
  endfunction
  assign missing_top.k_copy = k;
  assert property (@(posedge k) missing_inst.ok);
  always @(posedge k) assert (missing_inst.ok2);
endinterface

// An interface without instances still sizes its members by constant functions
interface WBus #(
    parameter int P = 3
);
  function automatic int calc(input int n);
    return n + 2;
  endfunction
  localparam int W = calc(P);
  logic [W-1:0] v;
  typedef struct packed {logic [3:0] value;} rec_t;
  function automatic int calc_struct(input int n);
    rec_t r;
    r.value = 4'd2;
    return n + int'(r.value);
  endfunction
  localparam int W2 = calc_struct(P);
  logic [W2-1:0] v2;
  function automatic int calc_arg(input rec_t a);
    return int'(a.value) + 2;
  endfunction
  localparam int W3 = calc_arg(rec_t'(4'(P)));
  logic [W3-1:0] v3;
  if (P > 1) begin : g
    always @(v) missing_inst.copy = v;
  end
  // Named blocks inside other statements of such code stay declared
  always @(v) begin
    if (v[0]) begin : if_blk
      logic [4:0] ix;
      ix = missing_inst.ia;
    end
    case (v[1])
      1'b0: begin : case_blk
        logic [5:0] cx;
        cx = missing_inst.ca;
      end
      default: ;
    endcase
    if (v[2]) begin
      begin : nest_blk
        logic [7:0] nx;
        nx = missing_inst.na;
      end
    end
    repeat (2) begin : loop_blk
      logic [6:0] lx;
      lx = missing_inst.la;
    end
  end
  logic [$bits(if_blk.ix)-1:0] iv;
  logic [$bits(case_blk.cx)-1:0] cv;
  logic [$bits(loop_blk.lx)-1:0] lv;
  logic [$bits(nest_blk.nx)-1:0] nv;
endinterface

class cls;
  virtual QBus vif1;

  function void foo(virtual QBus vif2);
    vif2.data = 1;
    vif2.poke(1);
  endfunction
endclass

module t;

  cls bar;
  virtual WBus #(5) wb;

  initial begin
    if ($bits(wb.v) != 7) $stop;
    if ($bits(wb.v2) != 7) $stop;
    if ($bits(wb.v3) != 7) $stop;
    if ($bits(wb.iv) != 5) $stop;
    if ($bits(wb.cv) != 6) $stop;
    if ($bits(wb.lv) != 7) $stop;
    if ($bits(wb.nv) != 8) $stop;
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
