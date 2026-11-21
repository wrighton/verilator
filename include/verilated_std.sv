// DESCRIPTION: Verilator: built-in packages and classes
//
// Code available from: https://verilator.org
//
//*************************************************************************
//
// This program is free software; you can redistribute it and/or modify it
// under the terms of either the GNU Lesser General Public License Version 3
// or the Perl Artistic License Version 2.0.
// SPDX-FileCopyrightText: 2022-2026 Wilson Snyder
// SPDX-License-Identifier: LGPL-3.0-only OR Artistic-2.0
//
//*************************************************************************
///
/// \file
/// \brief Verilated IEEE std:: header
///
/// This file is included automatically by Verilator, unless '--no-std-package'
/// is used.
///
/// This file is not part of the Verilated public-facing API.
/// It is only for internal use.
///
//*************************************************************************
//
// The following keywords from this file are hardcoded for detection in the parser:
// "mailbox", "process", "randomize", "semaphore", "std"

`ifndef VERILATOR_STD_SV_
`define VERILATOR_STD_SV_

// verilator lint_off DECLFILENAME
// verilator lint_off TIMESCALEMOD
// verilator lint_off UNUSEDSIGNAL
// verilator lint_off VARHIDDEN
// Library code, not the user's design
// verilator coverage_off
package std;
  // IEEE 1800-specified standard "mailbox"
  class mailbox #(
      type T
  );
    protected int m_bound;
    protected T m_queue[$];
`ifdef VERILATOR_TIMING
    // Waiting queues, which only this code uses: V3Param makes them wait queues of the timing
    // scheduler (see VlWaitQueue). A process waits only if the mailbox is empty, or full for a
    // put(), and then behind those waiting already, as the waiting queue is first-in first-out
    // (IEEE 1800-2023 15.4.5). A wake resumes only the first one, which passes the turn on when
    // it proceeds, with the messages or the room it leaves.
    // The processes in get() or peek() wait for a message on the first, and the processes in
    // put() of a bounded mailbox wait for room on the second.
    local chandle m_getQueue;
    local chandle m_putQueue;
`endif

    function new(int bound = 0);
      m_bound = bound;
    endfunction

    function int num();
      return m_queue.size();
    endfunction

    task put(T message);
`ifdef VERILATOR_TIMING
      if (m_putQueue.__Vpolled()) begin
        // Waits as a process testing its condition, as the design has a wait condition that may
        // change a mailbox as the triggers are evaluated (see V3Timing)
        while (m_bound != 0 && m_queue.size() >= m_bound)  //
          wait (m_queue.size() < m_bound);
        m_queue.push_back(message);
      end
      else begin
        if (m_bound != 0) begin
          // Waits its turn on the wait queue, which only the process that waited ends. Two
          // event controls, as GCC -Os compiles one into code that loads the resume index of
          // the coroutine wider than it stored it, which made this task 8% slower when it does
          // not wait.
          if (m_queue.size() >= m_bound) begin
            @m_putQueue;
            while (m_queue.size() >= m_bound) @m_putQueue;
            m_queue.push_back(message);
            m_putQueue.__Vrelease(m_bound - m_queue.size());
          end
          else begin
            m_queue.push_back(message);
            if (m_putQueue.__Vlisted()) m_putQueue.__Vtake(m_bound - m_queue.size());
          end
        end
        else begin
          m_queue.push_back(message);
        end
        if (m_getQueue.__Vlisted()) m_getQueue.__Vwake(m_queue.size());
      end
`endif
    endtask

    // Does not wait, so it may pass the processes waiting
    function int try_put(T message);
      if (m_bound == 0 || num() < m_bound) begin
        m_queue.push_back(message);
`ifdef VERILATOR_TIMING
        if (m_getQueue.__Vlisted()) m_getQueue.__Vwake(m_queue.size());
        if (m_putQueue.__Vlisted()) m_putQueue.__Vtake(m_bound - m_queue.size());
`endif
        return 1;
      end
      return 0;
    endfunction

    task get(ref T message);
`ifdef VERILATOR_TIMING
      // As in put()
      if (m_getQueue.__Vpolled()) begin
        while (m_queue.size() == 0) begin
          wait (m_queue.size() > 0);
        end
        message = m_queue.pop_front();
      end
      else begin
        if (m_queue.size() == 0) begin
          @m_getQueue;
          while (m_queue.size() == 0) @m_getQueue;
          message = m_queue.pop_front();
          m_getQueue.__Vrelease(m_queue.size());
        end
        else begin
          message = m_queue.pop_front();
          if (m_getQueue.__Vlisted()) m_getQueue.__Vtake(m_queue.size());
        end
        if (m_putQueue.__Vlisted()) m_putQueue.__Vwake(m_bound - m_queue.size());
      end
`endif
    endtask

    // Does not wait, so it may pass the processes waiting
    function int try_get(ref T message);
      if (num() > 0) begin
        // A typeless mailbox message must match the type of the variable (IEEE 1800-2023 15.4.6)
        if ($c("!VlMailboxMessage::match(", message, ", ", m_queue[0], ")")) return -1;
        message = m_queue.pop_front();
`ifdef VERILATOR_TIMING
        if (m_getQueue.__Vlisted()) m_getQueue.__Vtake(m_queue.size());
        if (m_putQueue.__Vlisted()) m_putQueue.__Vwake(m_bound - m_queue.size());
`endif
        return 1;
      end
      return 0;
    endfunction

    task peek(ref T message);
`ifdef VERILATOR_TIMING
      // As in put(). The message stays, so the next waiter may proceed too
      // (IEEE 1800-2023 15.4.7).
      if (m_getQueue.__Vpolled()) begin
        while (m_queue.size() == 0) begin
          wait (m_queue.size() > 0);
        end
        message = m_queue[0];
      end
      else begin
        if (m_queue.size() == 0) begin
          @m_getQueue;
          while (m_queue.size() == 0) @m_getQueue;
          message = m_queue[0];
          m_getQueue.__Vrelease(m_queue.size());
        end
        else begin
          message = m_queue[0];
        end
      end
`endif
    endtask

    function int try_peek(ref T message);
      if (num() > 0) begin
        // A typeless mailbox message must match the type of the variable (IEEE 1800-2023 15.4.8)
        if ($c("!VlMailboxMessage::match(", message, ", ", m_queue[0], ")")) return -1;
        message = m_queue[0];
        return 1;
      end
      return 0;
    endfunction
  endclass

  // IEEE 1800-specified standard "process"
  class process;
    typedef enum {
      FINISHED = 0,
      RUNNING = 1,
      WAITING = 2,
      SUSPENDED = 3,
      KILLED = 4
    } state;

    // Width visitor changes it to VlProcessRef
    // V3Name is hardcoded not to rename or --protect-ids this variable
    protected chandle m_process;

    static function process self();
      process p;
`ifdef VERILATOR_TIMING
      $c("vlProcess->initFromSelf(", p, ");");
      if (p == null) begin
        p = new;
        $c(p.m_process, " = vlProcess;");
        $c("vlProcess->setSelf(&*", p, ");");
      end
`else
      p = new;
`endif
      return p;
    endfunction

    protected function void set_status(state s);
`ifdef VERILATOR_TIMING
      $c(m_process, "->state(", s, ");");
`endif
    endfunction

    function state status();
`ifdef VERILATOR_TIMING
      return state'($cpure(m_process, "->state()"));
`else
      return RUNNING;
`endif
    endfunction

    function void kill();
`ifdef VERILATOR_TIMING
      // IEEE 1800-2023 9.7: kill() terminates the process and all its descendants
      $c(m_process, "->disable();");
`endif
    endfunction

    function void suspend();
      $error("std::process::suspend() not supported");
    endfunction

    function void resume();
      set_status(RUNNING);
    endfunction

    task await();
`ifdef VERILATOR_TIMING
      wait (status() == FINISHED || status() == KILLED);
`endif
    endtask

    static function void killQueue(ref process processQueue[$]);
`ifdef VERILATOR_TIMING
      repeat (processQueue.size()) begin
        process p = processQueue.pop_front();
        if (p) p.kill();
      end
`endif
    endfunction

    // verilog_format: off
`ifdef VERILATOR_TIMING
`systemc_dtor
    if (m_process) m_process->clearSelf(this);
`verilog
`endif
    // verilog_format: on

    function string get_randstate();
      // Initialize with $c to ensure it won't be constified
      string s = string'($c("0"));

      $c(s, " = ", m_process, "->randstate();");
      return s;
    endfunction

    function void set_randstate(string s);
      $c(m_process, "->randstate(", s, ");");
    endfunction
  endclass

  // IEEE 1800-specified standard "semaphore"
  class semaphore;
    typedef struct {
      process proc;
      int reqKeys;
    } procKeys;
    procKeys m_queue[$];
    protected int m_keyCount;

    local task dropKilled;
      // Drop killed processes from the queue
`ifdef VERILATOR_TIMING
      while (m_queue.size() > 0 && m_queue[0].proc.status() == process::KILLED) m_queue.pop_front();
`endif
    endtask
    function new(int keyCount = 0);
      m_keyCount = keyCount;
    endfunction

    function void put(int keyCount = 1);
      m_keyCount += keyCount;
    endfunction

    task get(int keyCount = 1);
`ifdef VERILATOR_TIMING
      dropKilled();
      // Fast path: take if keys fit AND either no one is queued, or
      // the head still doesn't fit (so we're not stealing its keys).
      if (m_keyCount >= keyCount && (m_queue.size() == 0 || m_queue[0].reqKeys > keyCount)) begin
        m_keyCount -= keyCount;
        return;
      end
      m_queue.push_back('{process::self(), keyCount});
      while (m_queue[0].proc != process::self()) begin
        wait (m_queue[0].proc.status() == process::KILLED || m_queue[0].proc == process::self());
        dropKilled();
      end
      wait (m_keyCount >= keyCount);
      m_keyCount -= keyCount;
      m_queue.pop_front();
`endif
    endtask

    function int try_get(int keyCount = 1);
      if (m_keyCount < keyCount) return 0;
      m_keyCount -= keyCount;
      return 1;
    endfunction
  endclass

  // IEEE 1800-specified standard "std::randomize"
  function int randomize();
    randomize = 0;
  endfunction

  // IEEE 1800-2023 19.10 coverage option and type_options
  // IEEE does not define these as std:: structures but Verilator uses
  // them as such currently, so named with a unique prefix
  typedef struct {
    string name;
    int weight = 1;
    int goal;
    string comment;
    int at_least;
    int auto_bin_max;
    int cross_num_print_missing;
    bit cross_retain_auto_bins;
    bit detect_overlap;
    bit per_instance;
    bit get_inst_coverage;
  } vl_covergroup_options_t;

  typedef struct {
    int weight = 1;
    int goal;
    string comment;
    int at_least;
    int auto_bin_max;
    bit detect_overlap;
  } vl_coverpoint_options_t;

  typedef struct {
    int weight = 1;
    int goal;
    string comment;
    int at_least;
    int cross_num_print_missing;
    bit cross_retain_auto_bins;
  } vl_cross_options_t;

  typedef struct {
    int weight = 1;
    int goal;
    string comment;
    bit strobe;
    bit merge_instances;
    bit distribute_first;
    real real_interval;
  } vl_covergroup_type_options_t;

  typedef struct {
    int weight = 1;
    int goal;
    string comment;
    real real_interval;
  } vl_coverpoint_type_options_t;

  typedef struct {
    int weight = 1;
    int goal;
    string comment;
  } vl_cross_type_options_t;

endpackage

`endif  // Guard
