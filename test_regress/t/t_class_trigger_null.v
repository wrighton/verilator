// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Cameron Waite
// SPDX-License-Identifier: CC0-1.0

// Test for null pointer dereference when sensitivity expressions reference
// class members. Verilator evaluates trigger expressions at simulation start,
// even for tasks that haven't been called yet. This caused null pointer
// dereference when accessing class_handle.event or class_handle.vif.signal
// because the task parameter didn't have a valid value yet.
//
// Also tests "instant fall-through" scenario: events triggered at time 0
// (same timestep as class construction) should still be detected.

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

interface my_if;
  logic sig;
endinterface

package my_pkg;

  class my_driver;
    virtual my_if vif;
    event my_event;
    int cnt;
    logic [2:0] vec;
    my_driver peer;

    function new(virtual my_if vif_in);
      vif = vif_in;
    endfunction
  endclass

  // Task with sensitivity expressions on class member event and signals
  task automatic my_task(my_driver drv, output int ev_cnt, pos_cnt, neg_cnt);
    my_driver h = drv;

    if (h == null) begin
      $display("Error: drv is NULL!");
      $finish;
    end

    fork
      begin
        // Wait on class member event - previously caused null deref
        @(h.my_event);
        ev_cnt++;
      end
      begin
        // Wait on posedge through virtual interface - previously caused null deref
        @(posedge h.vif.sig);
        pos_cnt++;
      end
      begin
        // Wait on negedge through virtual interface - previously caused null deref
        @(negedge h.vif.sig);
        neg_cnt++;
      end
      begin
        #10;
        ->h.my_event;
        #10;
        h.vif.sig = 1;
        #10;
        h.vif.sig = 0;
      end
    join
  endtask

  // Wait on an expression of a member through a task argument
  task automatic wait_cnt(my_driver drv, int n);
    wait (drv.cnt == n);
  endtask

endpackage

module t;
  my_if intf ();
  my_pkg::my_driver drv;
  virtual my_if vif;

  int event_count;
  int posedge_count;
  int negedge_count;

  // Counter for instant (time 0) event detection
  int instant_event_count = 0;

  // Test "instant fall-through": sensitivity on class member event at module level
  // This always block is evaluated at elaboration when drv is still null.
  // After construction, events triggered at time 0 should still be detected.
  always @(drv.my_event) begin
    instant_event_count++;
  end

  // Sensitivity through a virtual interface that is null until the initial block below sets it.
  // The NBA keeps the process clocked, rather than combinational.
  int vif_sig_count = 0;
  always @(vif.sig) if ($time > 0) vif_sig_count <= vif_sig_count + 1;
  // Two changes, at times 40 and 50, by the task called below
  initial begin
    #60;
    if (vif_sig_count != 2) begin
      $display("%%Error: vif_sig_count = %0d, expected 2", vif_sig_count);
      $stop;
    end
  end

  // Sensitivity on an expression of a member, on a select of a member, and on a member of a
  // member. The processes wait only once the handles they read through are set, but the
  // triggers are also computed at time 0, before the initial block below constructs 'drv'.
  int wait_count = 0;
  initial begin
    #1;
    wait (drv.cnt == 2);
    ++wait_count;
  end
  int task_wait_count = 0;
  initial begin
    #20;
    my_pkg::wait_cnt(drv, 2);
    ++task_wait_count;
  end
  int bit_count = 0;
  initial begin
    #1;
    @(posedge drv.vec[1]);
    ++bit_count;
  end
  int peer_count = 0;
  initial begin
    #66;
    @(drv.peer.cnt);
    ++peer_count;
  end
  // The right operand of '||' is read only when the handle is set, so the posedge from
  // clearing the handle must not be suppressed
  int or_count = 0;
  initial begin
    #1;
    forever begin
      @(posedge (drv.peer == null || drv.peer.cnt[0]));
      ++or_count;
    end
  end
  initial begin
    #65;
    drv.cnt = 2;
    drv.vec = 3'b010;
    drv.peer = new(vif);
    #2 drv.peer.cnt = 1;
    #1 drv.peer.cnt = 0;
    #1 drv.peer = null;
    #1;
    `checkd(wait_count, 1);
    `checkd(task_wait_count, 1);
    `checkd(bit_count, 1);
    `checkd(peer_count, 1);
    `checkd(or_count, 2);
  end

  // A member selected by a runtime value of '&&', '||' or '?:', or read by an 'iff' condition,
  // through a handle that is null until time 2. The processes wait only from time 3. 'gate' is
  // written below, so the selections are not constant.
  my_pkg::my_driver sel_drv;
  bit gate = 1;
  bit tick = 0;
  int and_count = 0, nor_count = 0, cond_count = 0, iff_count = 0;
  initial begin
    #3;
    @(posedge (gate && sel_drv.vec[0]));
    ++and_count;
  end
  initial begin
    #3;
    @(posedge (!gate || sel_drv.vec[0]));
    ++nor_count;
  end
  initial begin
    #3;
    @(posedge (gate ? sel_drv.vec[0] : 1'b0));
    ++cond_count;
  end
  initial begin
    #3;
    @(tick iff sel_drv.vec[1]);
    ++iff_count;
  end
  initial begin
    #2 sel_drv = new(vif);
    #2 sel_drv.vec = 3'b011;
    gate = 1;
    #1 tick = 1;
    #1;
    `checkd(and_count, 1);
    `checkd(nor_count, 1);
    `checkd(cond_count, 1);
    `checkd(iff_count, 1);
  end

  // Construct the class at time 0
  initial begin
    vif = intf;
    drv = new(vif);
    intf.sig = 0;
  end

  // Trigger event at time 0 (same timestep as construction) - "instant fall-through"
  // Use #0 to ensure construction happens first in delta cycle ordering
  initial begin
    #0;
    ->drv.my_event;
  end

  // Call the task later - trigger expressions were evaluated before this
  initial begin
    event_count = 0;
    posedge_count = 0;
    negedge_count = 0;

    #20;
    my_pkg::my_task(drv, event_count, posedge_count, negedge_count);

    // Verify all triggers occurred
    if (event_count != 1) begin
      $display("%%Error: event_count = %0d, expected 1", event_count);
      $stop;
    end
    if (posedge_count != 1) begin
      $display("%%Error: posedge_count = %0d, expected 1", posedge_count);
      $stop;
    end
    if (negedge_count != 1) begin
      $display("%%Error: negedge_count = %0d, expected 1", negedge_count);
      $stop;
    end

    // Verify instant fall-through worked (time 0 event was detected)
    // We expect 2: one from time 0, one from the task at time 30
    if (instant_event_count != 2) begin
      $display("%%Error: instant_event_count = %0d, expected 2", instant_event_count);
      $display("%%Error: Instant fall-through failed - events at time 0 were missed!");
      $stop;
    end
  end

  initial begin
    #100;
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
