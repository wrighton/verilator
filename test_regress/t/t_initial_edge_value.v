// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

// With --x-initial-edge, time 0 emulates a transition from X: an expression that
// is 1 at time 0 has a posedge only (X->1), one that is 0 a negedge only (X->0)
// (IEEE 1800-2023 9.4.2).

interface ifc;
  logic clk;
endinterface

class Cls;
  virtual ifc vif;
endclass

module t;

  // Variables set by an initial block below
  logic rst_n;
  logic set_n;

  // Processes waiting before the initial assignment see its edge
`ifdef VERILATOR_TIMING
  int task_pos = 0;
  int task_neg = 0;
  task automatic wait_pos;
    @(posedge rst_n);
    task_pos++;
  endtask
  task automatic wait_neg;
    @(negedge rst_n);
    task_neg++;
  endtask
  initial wait_pos();
  initial wait_neg();
  final begin
    `checkd(task_pos, 0);
    `checkd(task_neg, 1);
  end
`endif

  // Constant nets; the matching edge may be optimized away (e.g. with --no-timing)
  wire w0 = 1'b0;
  wire w1 = 1'b1;
  int pos_w0 = 0;
  int neg_w0 = 0;
  int pos_w1 = 0;
  int neg_w1 = 0;
  always @(posedge w0) pos_w0++;
  always @(negedge w0) neg_w0++;
  always @(posedge w1) pos_w1++;
  always @(negedge w1) neg_w1++;
  final begin
    `checkd(pos_w0, 0);
    `checkd(neg_w0 <= 1, 1'b1);
    `checkd(pos_w1 <= 1, 1'b1);
    `checkd(neg_w1, 0);
  end

  // Variables set by an initial block
  int pos_rst = 0;
  int neg_rst = 0;
  int pos_set = 0;
  int neg_set = 0;
  always @(posedge rst_n) pos_rst++;
  always @(negedge rst_n) neg_rst++;
  always @(posedge set_n) pos_set++;
  always @(negedge set_n) neg_set++;
  initial begin
    rst_n = 1'b0;
    set_n = 1'b1;
  end
  final begin
    `checkd(pos_rst, 0);
    `checkd(neg_rst, 1);
    `checkd(pos_set, 1);
    `checkd(neg_set, 0);
  end

  // An expression
  int pos_xor = 0;
  int neg_xor = 0;
  always @(posedge (rst_n ^ set_n)) pos_xor++;
  always @(negedge (rst_n ^ set_n)) neg_xor++;
  final begin
    `checkd(pos_xor, 1);
    `checkd(neg_xor, 0);
  end

  // Value change and both edges fire once
  int chg_rst = 0;
  int edge_set = 0;
  always @(rst_n) chg_rst++;
  always @(edge set_n) edge_set++;
  final begin
    `checkd(chg_rst, 1);
    `checkd(edge_set, 1);
  end

  // The iff condition qualifies the time 0 edge
  logic en0;
  logic en1;
  int neg_rst_en0 = 0;
  int neg_rst_en1 = 0;
  always @(negedge rst_n iff en0) neg_rst_en0++;
  always @(negedge rst_n iff en1) neg_rst_en1++;
  initial begin
    en0 = 1'b0;
    en1 = 1'b1;
  end
  final begin
    `checkd(neg_rst_en0, 0);
    `checkd(neg_rst_en1, 1);
  end

  // Multi-bit expressions use their LSB
  logic [69:0] wide;
  logic [3:1] narrow;
  int pos_wide = 0;
  int neg_wide = 0;
  int pos_narrow = 0;
  int neg_narrow = 0;
  always @(posedge wide) pos_wide++;
  always @(negedge wide) neg_wide++;
  always @(posedge narrow) pos_narrow++;
  always @(negedge narrow) neg_narrow++;
  initial begin
    wide = {1'b1, 68'h0, 1'b0};
    narrow = 3'b001;
  end
  final begin
    `checkd(pos_wide, 0);
    `checkd(neg_wide, 1);
    `checkd(pos_narrow, 1);
    `checkd(neg_narrow, 0);
  end

  // Through a class handle and a virtual interface, both possibly null
  ifc i_ifc ();
  Cls cls;
  int pos_cls = 0;
  int neg_cls = 0;
  always @(posedge cls.vif.clk) pos_cls++;
  always @(negedge cls.vif.clk) neg_cls++;
  initial begin
    cls = new;
    cls.vif = i_ifc;
    i_ifc.clk = 1'b1;
  end
  final begin
    `checkd(pos_cls, 1);
    `checkd(neg_cls, 0);
  end

  // A named event has no X state
  event ev;
  int ev_cnt = 0;
  always @(ev) ev_cnt++;
  final `checkd(ev_cnt, 0);

  // Asynchronous reset flop with an idle clock: reset, but no clock edge
  logic clk;
  logic q;
  int clk_cnt = 0;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) q <= 1'b1;
    else q <= 1'b0;
  end
  always @(posedge clk) clk_cnt++;
  initial clk = 1'b0;
  final begin
    `checkd(q, 1'b1);
    `checkd(clk_cnt, 0);
    $write("*-* All Finished *-*\n");
  end

endmodule
