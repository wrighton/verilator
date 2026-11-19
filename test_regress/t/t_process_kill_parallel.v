// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// For killing through a virtual interface
interface kill_if;
  process target;
  function void kill_target();
    target.kill();
  endfunction
endinterface

// Pairs of clocked blocks, which may be in different parallel MTasks, control processes in the
// same cycles (IEEE 1800-2023 9.3.2, 9.6.2, 9.7). Each block only uses its own state and the
// cycle count, so only the process control orders them.
module t;
  timeunit 1ns; timeprecision 1ps;

  localparam int PAIRS = 4;
  localparam int FIRST = 2;  // Cycle of the first kill
  localparam realtime WAKE = 100ns;  // When a killed process would have woken up
  localparam realtime AFTER = 3ns;  // A delay after a join ended by kills

  logic clk = 1'b0;
  always #5ns clk = ~clk;
  int cyc = 0;
  always_ff @(posedge clk) cyc <= cyc + 1;

  int ran = 0;  // Killed processes that ran on after WAKE

  // A process and its forked parent
  process parents[PAIRS];
  process children[PAIRS];
  for (genvar g = 0; g < PAIRS; ++g) begin : gen_parent
    initial
    fork
      begin
        parents[g] = process::self();
        fork
          begin
            children[g] = process::self();
            #WAKE ran++;
          end
        join_none
        #WAKE ran++;
      end
    join_none
  end

  // Two branches of one join; the parent passes the join once, then runs on
  process sib_a[PAIRS];
  process sib_b[PAIRS];
  int sib_joined[PAIRS];
  time sib_join_time[PAIRS];
  int sib_after[PAIRS];
  for (genvar g = 0; g < PAIRS; ++g) begin : gen_sib
    initial begin
      fork
        begin
          sib_a[g] = process::self();
          #WAKE ran++;
        end
        begin
          sib_b[g] = process::self();
          #WAKE ran++;
        end
      join
      ++sib_joined[g];
      sib_join_time[g] = $time;
      #AFTER++sib_after[g];
    end
  end

  // The only branches of two joins; both parents run on
  process solo_a[PAIRS];
  process solo_b[PAIRS];
  int solo_after_a[PAIRS];
  int solo_after_b[PAIRS];
  for (genvar g = 0; g < PAIRS; ++g) begin : gen_solo
    initial begin
      fork
        begin
          solo_a[g] = process::self();
          #WAKE ran++;
        end
      join
      #AFTER++solo_after_a[g];
    end
    initial begin
      fork
        begin
          solo_b[g] = process::self();
          #WAKE ran++;
        end
      join
      #AFTER++solo_after_b[g];
    end
  end

  always_ff @(posedge clk) begin
    if (cyc >= FIRST && cyc < FIRST + PAIRS) begin
      children[cyc-FIRST].kill();
      sib_a[cyc-FIRST].kill();
      solo_a[cyc-FIRST].kill();
    end
  end
  always_ff @(posedge clk) begin
    if (cyc >= FIRST && cyc < FIRST + PAIRS) begin
      parents[cyc-FIRST].kill();
      sib_b[cyc-FIRST].kill();
      solo_b[cyc-FIRST].kill();
    end
  end

  // Two branches of one join, killed through a virtual function whose override does not have
  // the 'virtual' keyword
  class Killer;
    virtual function void kill_target();
    endfunction
  endclass
  class TargetKiller extends Killer;
    process target;
    function void kill_target();
      target.kill();
    endfunction
  endclass
  Killer vkill_a[PAIRS];
  Killer vkill_b[PAIRS];
  int vsib_joined[PAIRS];
  int vsib_after[PAIRS];
  for (genvar g = 0; g < PAIRS; ++g) begin : gen_vsib
    initial begin
      TargetKiller ka;
      TargetKiller kb;
      ka = new;
      kb = new;
      vkill_a[g] = ka;
      vkill_b[g] = kb;
      fork
        begin
          ka.target = process::self();
          #WAKE ran++;
        end
        begin
          kb.target = process::self();
          #WAKE ran++;
        end
      join
      ++vsib_joined[g];
      #AFTER++vsib_after[g];
    end
  end

  always_ff @(posedge clk) begin
    if (cyc >= FIRST && cyc < FIRST + PAIRS) vkill_a[cyc-FIRST].kill_target();
  end
  always_ff @(posedge clk) begin
    if (cyc >= FIRST && cyc < FIRST + PAIRS) vkill_b[cyc-FIRST].kill_target();
  end

  // Two branches of one join, killed through virtual interfaces
  kill_if kif_a ();
  kill_if kif_b ();
  virtual kill_if vkif_a = kif_a;
  virtual kill_if vkif_b = kif_b;
  int isib_joined = 0;
  int isib_after = 0;
  initial begin
    fork
      begin
        kif_a.target = process::self();
        #WAKE ran++;
      end
      begin
        kif_b.target = process::self();
        #WAKE ran++;
      end
    join
    ++isib_joined;
    #AFTER++isib_after;
  end

  always_ff @(posedge clk) if (cyc == FIRST) vkif_a.kill_target();
  always_ff @(posedge clk) if (cyc == FIRST) vkif_b.kill_target();

  // Two named branches of one join, disabled by name
  int nd_joined = 0;
  time nd_join_time = 0;
  int nd_after = 0;
  initial begin
    fork
      begin : nd_a
        #WAKE ran++;
      end
      begin : nd_b
        #WAKE ran++;
      end
    join
    ++nd_joined;
    nd_join_time = $time;
    #AFTER++nd_after;
  end

  always_ff @(posedge clk) if (cyc == FIRST) disable nd_a;
  always_ff @(posedge clk) if (cyc == FIRST) disable nd_b;

  // Processes started through a function, which wait
  class Launcher;
    int done = 0;
    task launch();
      fork
        #AFTER++done;
      join_none
    endtask
  endclass
  Launcher launch_a = new;
  Launcher launch_b = new;

  always @(posedge clk) begin
    if (cyc >= FIRST && cyc < FIRST + PAIRS) launch_a.launch();
  end
  always @(posedge clk) begin
    if (cyc >= FIRST && cyc < FIRST + PAIRS) launch_b.launch();
  end

  initial begin
    #(2 * WAKE);
    for (int i = 0; i < PAIRS; ++i) begin
      `checkd(parents[i].status(), process::KILLED);
      `checkd(children[i].status(), process::KILLED);
      `checkd(sib_a[i].status(), process::KILLED);
      `checkd(sib_b[i].status(), process::KILLED);
      `checkd(sib_joined[i], 1);
      `checkd(sib_join_time[i], 25 + 10 * i);
      `checkd(sib_after[i], 1);
      `checkd(solo_after_a[i], 1);
      `checkd(solo_after_b[i], 1);
      `checkd(vsib_joined[i], 1);
      `checkd(vsib_after[i], 1);
    end
    `checkd(isib_joined, 1);
    `checkd(isib_after, 1);
    `checkd(nd_joined, 1);
    `checkd(nd_join_time, 25);
    `checkd(nd_after, 1);
    `checkd(launch_a.done, PAIRS);
    `checkd(launch_b.done, PAIRS);
    `checkd(ran, 0);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
