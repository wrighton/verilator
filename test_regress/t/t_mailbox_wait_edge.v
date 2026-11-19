// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// A process taking a message raises a signal, and puts a message for another process, which
// lowers it. The rise comes before that put, which wakes the other process, so the edge is seen
// (IEEE 1800-2023 9.4.2). The same with processes of a class, and through bounded mailboxes,
// where the second process waits for room; when the message the other process was woken for
// was taken before, by try_get(); and when one taken while the turn passes is replaced.
module t;
  timeunit 1ns; timeprecision 1ps;

  mailbox #(int) a = new;
  mailbox #(int) b = new;
  logic pulse = 1'b0;
  int edges = 0;
  always @(posedge pulse) ++edges;
  initial begin
    int v;
    a.get(v);
    pulse = 1'b1;
    b.put(v);
  end
  initial begin
    int v;
    b.get(v);
    pulse = 1'b0;
  end

  class Pass;
    mailbox #(int) a = new;
    mailbox #(int) b;
    logic pulse = 1'b0;
    int edges = 0;
    function new(int bound);
      b = new(bound);
    endfunction
    task rise();
      int v;
      a.get(v);
      pulse = 1'b1;
      b.put(v);
    endtask
    task fall();
      int v;
      b.get(v);
      pulse = 1'b0;
    endtask
    // The get() frees the room the put() of the other process waits for
    task rise_room();
      int v;
      a.get(v);
      pulse = 1'b1;
      b.get(v);
    endtask
    task fall_room();
      b.put(2);
      pulse = 1'b0;
    endtask
    task count();
      forever begin
        @(posedge pulse);
        ++edges;
      end
    endtask
  endclass
  Pass p = new(0);
  Pass q = new(1);

  // The message 'cons' is woken for is taken before it resumes, and 'fwd', which waits on an
  // older wait list, puts another one, after raising the signal
  class Taken;
    mailbox #(int) r = new;
    mailbox #(int) q = new;
    logic pulse = 1'b0;
    int edges = 0;
    task fwd();
      int v;
      r.get(v);
      pulse = 1'b1;
      q.put(v);
    endtask
    task cons();
      int v;
      q.get(v);
      pulse = 1'b0;
    endtask
    task count();
      forever begin
        @(posedge pulse);
        ++edges;
      end
    endtask
    task send();
      int x;
      q.put(1);
      void'(q.try_get(x));
      r.put(2);
    endtask
  endclass
  Taken taken = new;

  // Two processes wait for the two messages of 'q', while 'rr' tries to take one, raises the
  // signal, and puts another one, which the second process lowers the signal for if it gets it.
  // Whichever takes the second message, the rise is seen. The same with room: two processes
  // wait to fill two slots, while 'rr' tries to fill one, raises the signal, and frees one.
  class Replaced;
    mailbox #(int) q;
    mailbox #(int) r = new;
    logic pulse = 1'b0;
    int edges = 0;
    int took = 0;  // By 'rr', of the messages or room
    function new(int bound);
      q = new(bound);
    endfunction
    task q1();
      int v;
      q.get(v);
    endtask
    task q2();
      int v;
      q.get(v);
      if (v == 3) pulse = 1'b0;
    endtask
    task rr();
      int v;
      int tmp;
      r.get(v);
      took = q.try_get(tmp);
      pulse = 1'b1;
      `checkd(q.try_put(3), 1);
    endtask
    task p1();
      q.put(1);
    endtask
    task p2();
      q.put(2);
      if (q.num() == 2) pulse = 1'b0;
    endtask
    task rr_room();
      int v;
      int tmp;
      r.get(v);
      took = q.try_put(9);
      pulse = 1'b1;
      `checkd(q.try_get(tmp), 1);
    endtask
    task count();
      forever begin
        @(posedge pulse);
        ++edges;
      end
    endtask
  endclass
  Replaced item = new(0);
  Replaced room = new(2);

  initial begin
    int v;
    fork
      taken.fwd();
      taken.count();
      item.count();
      room.count();
    join_none
    #1;
    fork
      taken.cons();
      item.q1();
      room.q.put(10);
      room.q.put(11);
    join_none
    #1;
    fork
      item.q2();
      room.p1();
    join_none
    #1;
    fork
      item.rr();
      room.p2();
    join_none
    #1;
    fork
      room.rr_room();
    join_none
    #1;
    taken.send();
    item.q.put(1);
    item.q.put(2);
    item.r.put(0);
    void'(room.q.try_get(v));
    void'(room.q.try_get(v));
    room.r.put(0);
    #3;
    `checkd(taken.edges, 1);
    `checkd(taken.q.num(), 0);
    `checkd(item.edges, 1);
    // Of the three messages, the two processes took two, and 'rr' one if it got one
    `checkd(item.q.num(), 1 - item.took);
    `checkd(room.edges, 1);
    // Of the two slots, the two processes filled two, and 'rr' one if it got one, then freed
    `checkd(room.q.num(), 1 + room.took);
  end

  initial begin
    q.b.put(0);
    fork
      p.rise();
      p.fall();
      p.count();
      q.rise_room();
      q.fall_room();
      q.count();
    join_none
    #5;
    a.put(1);
    p.a.put(1);
    q.a.put(1);
    #5;
    `checkd(edges, 1);
    `checkd(pulse, 1'b0);
    `checkd(p.edges, 1);
    `checkd(p.pulse, 1'b0);
    `checkd(q.edges, 1);
    `checkd(q.pulse, 1'b0);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
