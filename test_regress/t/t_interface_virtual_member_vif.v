// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Interface members of virtual interface type, written through a virtual interface

`timescale 1ns / 1ps

interface leaf_if;
  logic [3:0] flag;
  modport mp(input flag);
endinterface

typedef virtual leaf_if leaf_vif_t;

interface box_if;
  virtual leaf_if leaf_vif;
  leaf_vif_t leaf_vift;
  virtual leaf_if.mp leaf_vifm;
  virtual leaf_if leaf_vifs[2];
  function automatic void set(virtual leaf_if l);
    leaf_vif = l;
  endfunction
endinterface

interface top_if;
  virtual box_if box_vif;
  virtual top_if self_vif;  // Own type
endinterface

interface pleaf_if #(
    parameter int W = 4
);
  logic [W-1:0] flag;
endinterface

interface pbox_if #(
    parameter int W = 4
);
  virtual pleaf_if #(W) leaf_vif;
endinterface

class Holder;
  virtual box_if vb;
endclass

module t;
  leaf_if leaf ();
  leaf_if leaf2 ();
  box_if box ();
  box_if boxes[2] ();
  top_if top ();
  pleaf_if #(8) pleaf ();
  pbox_if #(8) pbox ();

  // Processes reading through the members, with change counters that are not inlined
  virtual box_if vbox = box;
  virtual top_if vtop = top;
  virtual pbox_if #(8) vpbox = pbox;
  leaf_vif_t tleaf = leaf2;  // Not a member
  logic [3:0] mirror;
  logic [3:0] mirror_v;
  logic [3:0] mirror_n;
  logic [3:0] mirror_d;
  logic [7:0] mirror_p;
  logic [3:0] mirror_t;
  logic [3:0] mirror_m;
  logic [3:0] mirror_a;
  int changes = 0;
  int changes_v = 0;
  int changes_n = 0;
  int changes_d = 0;
  int changes_p = 0;
  int changes_t = 0;
  int changes_m = 0;
  int changes_a = 0;
  always_comb mirror = box.leaf_vif == null ? 4'hf : box.leaf_vif.flag;
  always_comb mirror_v = vbox.leaf_vif == null ? 4'hf : vbox.leaf_vif.flag;
  always_comb
    mirror_n = vtop.box_vif == null || vtop.box_vif.leaf_vif == null ? 4'hf
             : vtop.box_vif.leaf_vif.flag;
  always_comb mirror_d = tleaf.flag;
  always_comb mirror_p = vpbox.leaf_vif == null ? 8'hff : vpbox.leaf_vif.flag;
  always_comb mirror_t = box.leaf_vift == null ? 4'hf : box.leaf_vift.flag;
  always_comb mirror_m = box.leaf_vifm == null ? 4'hf : box.leaf_vifm.flag;
  always_comb mirror_a = boxes[1].leaf_vif == null ? 4'hf : boxes[1].leaf_vif.flag;
  always @(mirror) changes++;
  always @(mirror_v) changes_v++;
  always @(mirror_n) changes_n++;
  always @(mirror_d) changes_d++;
  always @(mirror_p) changes_p++;
  always @(mirror_t) changes_t++;
  always @(mirror_m) changes_m++;
  always @(mirror_a) changes_a++;

  // Process waiting for the member, then for a member read through it
  time published = 0;
  time flagged = 0;
  initial begin
    wait (box.leaf_vif != null);
    published = $time;
    @(box.leaf_vif.flag);
    flagged = $time;
  end

  function automatic void publish(virtual box_if vb, virtual leaf_if vl);
    vb.leaf_vif = vl;
  endfunction

  task automatic publish_later(virtual box_if vb, virtual leaf_if vl);
    #1;
    vb.leaf_vif = vl;
    vb.leaf_vift = vl;
    vb.leaf_vifm = vl;
    vb.leaf_vifs[1] = vl;
  endtask

  // Each step writes after a delay, and checks after another delay, so that no write follows
  // a read in the same time step
  initial begin
    virtual box_if vb;
    virtual box_if vbs[2];
    virtual top_if vt;
    virtual leaf_if vl;
    virtual pbox_if #(8) vpb;
    virtual pleaf_if #(8) vpl;
    Holder h;
    int base;
    int base_v;
    int base_n;
    int base_d;
    int base_p;
    int base_a;
    int base_t;
    int base_m;
    vb = box;
    leaf.flag = 1;
    leaf2.flag = 5;
    #1;
    base = changes;  // Not counting the change at time 0
    base_v = changes_v;
    base_n = changes_n;
    base_d = changes_d;
    base_p = changes_p;
    base_a = changes_a;
    base_t = changes_t;
    base_m = changes_m;

    // Write through a virtual handle to the container, then through the member
    #1;
    publish(vb, leaf);
    #1;
    `checkd(box.leaf_vif == leaf, 1'b1);
    `checkd(published, 2);
    `checkd(changes, base + 1);
    `checkd(changes_v, base_v + 1);
    #1;
    vb.leaf_vif.flag = 2;
    #1;
    `checkd(leaf.flag, 2);
    `checkd(flagged, 4);
    `checkd(changes, base + 2);
    `checkd(changes_v, base_v + 2);

    // Write in a task with timing, also to typedef, modport and array members
    #1;
    publish_later(vb, leaf2);
    #1;
    `checkd(box.leaf_vif == leaf2, 1'b1);
    `checkd(changes, base + 3);
    `checkd(changes_v, base_v + 3);
    `checkd(changes_t, base_t + 1);
    `checkd(changes_m, base_m + 1);
    #1;
    vb.leaf_vift.flag = 6;
    #1;
    `checkd(leaf2.flag, 6);
    `checkd(changes, base + 4);
    `checkd(changes_d, base_d + 1);
    `checkd(changes_v, base_v + 4);
    `checkd(changes_t, base_t + 2);
    #1;
    vb.leaf_vifs[1].flag = 7;
    #1;
    `checkd(leaf2.flag, 7);
    `checkd(changes, base + 5);
    `checkd(changes_v, base_v + 5);
    `checkd(changes_d, base_d + 2);
    `checkd(changes_t, base_t + 3);
    `checkd(changes_m, base_m + 3);

    // Write to the previous leaf, no longer pointed to
    #1;
    vl = leaf;
    vl.flag = 9;
    #1;
    `checkd(leaf.flag, 9);
    `checkd(changes, base + 5);
    `checkd(changes_v, base_v + 5);

    // Write by an interface method called through a virtual interface
    #1;
    vb.set(leaf);
    #1;
    `checkd(box.leaf_vif == leaf, 1'b1);
    `checkd(changes, base + 6);
    `checkd(changes_v, base_v + 6);

    // Nested container
    #1;
    vt = top;
    vt.box_vif = box;
    vt.self_vif = top;
    vt.box_vif.leaf_vif = leaf2;
    #1;
    `checkd(changes, base + 7);
    `checkd(changes_v, base_v + 7);
    `checkd(changes_n, base_n + 1);
    #1;
    vt.box_vif.leaf_vif.flag = 8;
    #1;
    `checkd(leaf2.flag, 8);
    `checkd(changes, base + 8);
    `checkd(changes_v, base_v + 8);
    `checkd(changes_n, base_n + 2);
    `checkd(changes_d, base_d + 3);

    // Array of containers
    #1;
    vbs = boxes;
    vbs[0].leaf_vif = leaf2;
    vbs[1].leaf_vif = leaf;
    #1;
    `checkd(boxes[0].leaf_vif == leaf2, 1'b1);
    `checkd(changes_a, base_a + 1);
    #1;
    vbs[1].leaf_vif.flag = 3;
    #1;
    `checkd(leaf.flag, 3);
    `checkd(changes_a, base_a + 2);

    // Container handle held in a class
    #1;
    h = new;
    h.vb = box;
    h.vb.leaf_vif = leaf;
    #1;
    `checkd(changes, base + 9);
    `checkd(changes_v, base_v + 9);
    `checkd(changes_n, base_n + 3);
    #1;
    h.vb.leaf_vif.flag = 4;
    #1;
    `checkd(leaf.flag, 4);
    `checkd(changes, base + 10);
    `checkd(changes_v, base_v + 10);
    `checkd(changes_n, base_n + 4);

    // Parameterized interfaces
    #1;
    vpb = pbox;
    vpl = pleaf;
    vpl.flag = 8'h12;
    vpb.leaf_vif = pleaf;
    #1;
    `checkd(changes_p, base_p + 1);
    #1;
    vpl.flag = 8'h34;
    #1;
    `checkd(pleaf.flag, 8'h34);
    `checkd(changes_p, base_p + 2);

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
