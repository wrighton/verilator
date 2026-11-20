// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// The waiting queues of a mailbox are internal to it, whatever the warning settings, as only its
// methods keep its waiting processes informed
// verilator lint_off ENCAPSULATED
class Mine extends mailbox #(int);
  type(m_getQueue) copy;
  task wait_turn();
    @m_getQueue;
  endtask
  function void wake();
    Mine other = this;
    m_getQueue.__Vwake();
    other.m_putQueue.__Vwake();
  endfunction
endclass

typedef Mine mine_t;

interface ifc;
  mailbox #(int) mb = new;
endinterface

module t;
  mine_t m = new;
  mailbox #(int) b = new;
  ifc i ();
  var type(b.m_getQueue) q;
  localparam type queue_t = type(b.m_putQueue);
  queue_t pq;
  var type(b.m_putQueue.__Vlisted()) listed_t;
  typedef struct {type(b.m_putQueue) q;} queue_s;
  queue_s s;
  bit listed;
  string name;
  int dims;
  chandle c;
  initial begin
    m.wait_turn();
    m.wake();
    listed = b.m_putQueue.__Vlisted();
    listed = m.m_getQueue.__Vlisted();
    listed = t.b.m_getQueue.__Vlisted();
    listed = i.mb.m_putQueue.__Vlisted();
    name = $typename(b.m_getQueue);
    dims = $dimensions(b.m_putQueue);
    listed = type(b.m_getQueue) == type(chandle);
    c = b.m_getQueue;
    listed = b.m_putQueue == null;
    b.m_putQueue = null;
    $display("%p", b.m_getQueue);
    b.m_putQueue.__Vrelease(.remaining());
    b.m_putQueue.__Vrelease(, 1);
    @(posedge b.m_getQueue);
    dims = $bits(b.m_getQueue);
    b.m_getQueue.foo();
  end
endmodule
// verilator lint_on ENCAPSULATED
