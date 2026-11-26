// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

class Cls;
  int seen;
  task run();
    int x = 1;
    fork
      seen = x;
    join_none
    x = 2;
    #1;
  endtask
endclass

module t;
  // Test: a process polls a variable of its parent until the parent sets it
  bit poll_done;
  task automatic poll();
    bit stop = 0;
    fork
      while (!stop) #10;
    join_none
    #105;
    stop = 1;
    wait fork;
  endtask
  initial begin
    poll();
    `checkd($time, 110);
    poll_done = 1;
  end

  // Test: the same, when the parent resumes after the other process of a join_any ends
  bit poll_any_done;
  task automatic poll_any();
    bit stop = 0;
    fork
      while (!stop) #10;
      #35;
    join_any
    stop = 1;
    wait fork;
  endtask
  initial begin
    poll_any();
    `checkd($time, 40);
    poll_any_done = 1;
  end

  // Test: a process starts once its parent blocks, so it sees the parent's later writes
  int seen_later;
  task automatic read_later();
    int x = 1;
    fork
      seen_later = x;
    join_none
    x = 2;
    #1;
  endtask
  initial begin
    read_later();
    `checkd(seen_later, 2);
  end

  // Test: the same, when the parent blocks on #0
  int seen_zero;
  task automatic read_zero();
    int x = 1;
    fork
      seen_zero = x;
    join_none
    x = 3;
    #0;
  endtask
  initial begin
    read_zero();
    #1;
    `checkd(seen_zero, 3);
  end

  // Test: a process sees the writes of another process of the fork
  int seen_sibling;
  task automatic siblings();
    int x = 1;
    fork
      #1 x = 4;
      #2 seen_sibling = x;
    join_none
  endtask
  initial begin
    siblings();
    #3;
    `checkd(seen_sibling, 4);
  end

  // Test: a process sees later writes to an argument of its task
  int seen_arg;
  task automatic read_arg(int a);
    fork
      seen_arg = a;
    join_none
    a = a + 10;
  endtask
  initial begin
    read_arg(5);
    #1;
    `checkd(seen_arg, 15);
  end

  // Test: a process of a nested fork sees the variables of both enclosing processes
  int seen_outer;
  int seen_inner;
  task automatic nested();
    int x = 1;
    fork
      begin
        int y = 1;
        fork
          begin
            seen_outer = x;
            seen_inner = y;
          end
        join_none
        y = 8;
      end
    join_none
    x = 7;
    #1;
  endtask
  initial begin
    nested();
    `checkd(seen_outer, 7);
    `checkd(seen_inner, 8);
  end

  // Test: a class method behaves the same
  initial begin
    Cls c;
    c = new;
    c.run();
    `checkd(c.seen, 2);
  end

  // Test: processes of an initial block share its automatic variables
  initial begin
    automatic int x = 1;
    automatic int y = 1;
    automatic int seen;
    fork
      seen = x;
      #1 y = 2;
    join_none
    x = 9;
    #2;
    `checkd(seen, 9);
    `checkd(y, 2);
  end

  // Test: IEEE 1800-2023 9.3.2: each process has its own copy of the fork's variable, but it
  // reads the loop variable only once the loop, where its parent blocks, is done
  int got_k[$];
  int got_m[$];
  initial begin
    for (int j = 1; j <= 3; ++j) begin
      fork
        automatic int k = j;
        got_k.push_back(k);
        begin
          automatic int m = j;
          got_m.push_back(m);
        end
      join_none
    end
    #1;
    `checkd(got_k.size(), 3);
    `checkd(got_m.size(), 3);
    foreach (got_k[i]) `checkd(got_k[i], i + 1);
    foreach (got_m[i]) `checkd(got_m[i], 4);
  end

  // Test: a variable of the loop body keeps its value of each iteration
  int got_idx[$];
  initial begin
    for (int i = 0; i < 3; ++i) begin
      automatic int idx = i * 2;
      fork
        got_idx.push_back(idx);
      join_none
    end
    #1;
    `checkd(got_idx.size(), 3);
    foreach (got_idx[i]) `checkd(got_idx[i], i * 2);
  end

  // Test: a variable of the fork has the value when the fork starts
  int seen_init;
  initial begin
    automatic int v = 5;
    fork
      automatic int k = v;
      seen_init = k;
    join_none
    v = 6;
    #1;
    `checkd(seen_init, 5);
  end

  // Test: an NBA through a handle uses the values when it runs
  class Box;
    int v;
    int a[3];
  endclass
  Box box_nba;
  task automatic nba(Box b);
    int x = 1;
    b.v <= x;
    for (int i = 0; i < 3; ++i) b.a[i] <= i + 10;
    x = 2;
    #1;
  endtask
  initial begin
    box_nba = new;
    nba(box_nba);
    `checkd(box_nba.v, 1);
    foreach (box_nba.a[i]) `checkd(box_nba.a[i], i + 10);
  end

  // Test: an NBA uses the value of a variable a forked process writes later
  Box box_child;
  task automatic nba_child_write(Box b);
    int x = 1;
    fork
      #1 x = 5;
    join_none
    b.v <= x;
    x = 2;
    #2;
  endtask
  initial begin
    box_child = new;
    nba_child_write(box_child);
    `checkd(box_child.v, 1);
  end

  // Test: a forked process and an NBA read one variable; the process sees the parent's later
  // write (2), and the NBA the value when it runs (1)
  Box box_both;
  int seen_both;
  task automatic reader_and_nba(Box b);
    int x = 1;
    fork
      seen_both = x;
    join_none
    b.v <= x;
    x = 2;
    #1;
  endtask
  initial begin
    box_both = new;
    reader_and_nba(box_both);
    `checkd(seen_both, 2);
    `checkd(box_both.v, 1);
  end

  // Test: NBAs in a loop use the loop index when they run, also when a forked process writes it
  Box box_loop;
  task automatic nba_loop(Box b);
    int i;
    fork
      #1 i = 7;
    join_none
    for (i = 0; i < 3; ++i) b.a[i] <= i + 20;
    #2;
  endtask
  initial begin
    box_loop = new;
    nba_loop(box_loop);
    foreach (box_loop.a[i]) `checkd(box_loop.a[i], i + 20);
  end

  // Test: an NBA through a handle updates the object of the handle when the NBA runs (IEEE
  // 1800-2023 10.4.2), also when the task rebinds the handle before the update
  Box box_first;
  Box box_second;
  task automatic nba_rebind(Box b);
    b.v <= 6;
    b = box_second;
    #1;
  endtask
  initial begin
    box_first = new;
    box_second = new;
    nba_rebind(box_first);
    `checkd(box_first.v, 6);
    `checkd(box_second.v, 0);
  end

  // Test: the same, with the handle rebound in a loop
  Box box_iter[3];
  task automatic nba_rebind_loop();
    Box h;
    for (int i = 0; i < 3; ++i) begin
      h = box_iter[i];
      h.v <= i + 30;
    end
    #1;
  endtask
  initial begin
    foreach (box_iter[i]) box_iter[i] = new;
    nba_rebind_loop();
    foreach (box_iter[i]) `checkd(box_iter[i].v, i + 30);
  end

  // Test: the same, with the handle also read by a forked process, which sees the new handle
  Box box_old;
  Box box_new;
  Box box_seen;
  task automatic nba_rebind_shared();
    Box h = box_old;
    fork
      box_seen = h;
    join_none
    h.v <= 8;
    h = box_new;
    #1;
  endtask
  initial begin
    box_old = new;
    box_new = new;
    nba_rebind_shared();
    `checkd(box_old.v, 8);
    `checkd(box_new.v, 0);
    `checkd(box_seen == box_new, 1);
  end

  // Test: a process sees the parent's later writes to an object through a handle
  int seen_member;
  task automatic member(Box b);
    b.v = 1;
    fork
      seen_member = b.v;
    join_none
    b.v = 3;
    #1;
  endtask
  initial begin
    automatic Box b = new;
    member(b);
    `checkd(seen_member, 3);
  end

  // Test: an assertion action uses the values when the assertion runs (IEEE 1800-2023 16.14.6.1)
  logic clk = 0;
  always #5 clk = ~clk;
  int cyc = 0;
  int got_act[$];
  logic never = 0;
  always @(posedge clk) begin
    automatic int k;
    k = cyc;
    cyc <= cyc + 1;
    assert property (never until never)
    else got_act.push_back(k);
    k = 99;
  end
  initial begin
    #100;
    `checkd(got_act.size(), 10);
    foreach (got_act[i]) `checkd(got_act[i], i);
  end

  // Test: the same, when a forked process writes the variable before the action runs
  int cyc_w = 0;
  int got_act_w[$];
  always @(posedge clk) begin
    automatic int k;
    k = cyc_w;
    cyc_w <= cyc_w + 1;
    fork
      k = 99;
    join_none
    assert property (never until never)
    else got_act_w.push_back(k);
  end
  initial begin
    #100;
    `checkd(got_act_w.size(), 10);
    foreach (got_act_w[i]) `checkd(got_act_w[i], i);
  end

  initial begin
    #1000;
    `checkd(poll_done, 1);
    `checkd(poll_any_done, 1);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
