// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module t;
  localparam int N = 5;

  // Test: each process started in a loop has its own copy of the fork's automatic variable,
  // also when it waits on a nested fork
  int seen_join[N];
  int seen_join_any[N];
  int seen_delay[N];
  initial begin
    for (int i = 0; i < N; i++) begin
      fork
        automatic int id = i;
        begin
          fork
            #1 seen_join[id] = id + 1;
          join
        end
        begin
          fork
            #1 seen_join_any[id] = id + 1;
            #(10 * N);
          join_any
        end
        #1 seen_delay[id] = id + 1;
      join_none
    end
    #(N + 1);
    for (int i = 0; i < N; i++) begin
      `checkd(seen_join[i], i + 1);
      `checkd(seen_join_any[i], i + 1);
      `checkd(seen_delay[i], i + 1);
    end
  end

  // Test: each process calling a task has its own copy of the task's arguments
  int tick;
  int got[N];
  task automatic record_after(int idx, int base);
    fork
      wait (tick > base);
    join
    got[idx] = base;
  endtask
  initial begin
    for (int i = 0; i < N; i++) begin
      automatic int k = i;
      automatic int b = 3 * (N - i);
      fork
        record_after(k, b);
      join_none
    end
    repeat (4 * N) #1 ++tick;
    for (int i = 0; i < N; i++) `checkd(got[i], 3 * (N - i));
  end

  // Test: processes started by a task, itself called by each process of a loop
  int leaf_sum;
  function automatic int twice(int v);
    return 2 * v;
  endfunction
  task automatic leaf(int v);
    #1 leaf_sum += twice(v);
  endtask
  task automatic spawn_pair(int v);
    for (int j = 0; j < 2; j++) begin
      fork
        automatic int w = v + j;
        begin
          fork
            leaf(w);
          join
        end
      join_none
    end
  endtask
  initial begin
    for (int i = 0; i < N; i++) begin
      automatic int v = 10 * i;
      fork
        spawn_pair(v);
      join_none
    end
    #N;
    `checkd(leaf_sum, 2 * (2 * 10 * (N * (N - 1) / 2) + N));
  end

  // Test: processes started by a task called by processes that the caller waits for
  int spawned[N];
  task automatic spawn(int v, int w);
    fork
      #2 spawned[v] += w;
    join_none
  endtask
  initial begin
    for (int i = 0; i < N; i++) begin
      fork
        spawn(i, 1);
      join
      fork
        spawn(i, 10);
      join_any
    end
    #3;
    for (int i = 0; i < N; i++) `checkd(spawned[i], 11);
  end

  // Test: nonblocking assignments with delays to elements each process selects
  int nba_elem[N];
  initial begin
    for (int i = 0; i < N; i++) begin
      fork
        automatic int k = i;
        nba_elem[k] <= #1 k + 1;
      join_none
    end
    #2;
    for (int i = 0; i < N; i++) `checkd(nba_elem[i], i + 1);
  end

  // Test: a sampled value function reads the automatic variable of its own process
  int sampled_same[N];
  initial begin
    for (int i = 0; i < N; i++) begin
      fork
        automatic int k = i;
        repeat (2) begin
          #1;
          if ($sampled(k) == k) ++sampled_same[k];
        end
      join_none
    end
    #3;
    for (int i = 0; i < N; i++) `checkd(sampled_same[i], 2);
  end

  // Test: each process keeps its own values of its intra-assignment delays
  int intra[N];
  int intra_task[N];
  task automatic put_later(int k);
    intra_task[k] = #2 k * 10 + 1;
  endtask
  initial begin
    for (int i = 0; i < N; i++) begin
      fork
        automatic int k = i;
        intra[k] = #1 k * 10;
        put_later(k);
      join_none
    end
    #3;
    for (int i = 0; i < N; i++) begin
      `checkd(intra[i], i * 10);
      `checkd(intra_task[i], i * 10 + 1);
    end
  end

  // Test: calls in processes that do not wait
  int add_sum;
  task automatic add(int v);
    int w;
    w = 2 * v;
    add_sum += w;
  endtask
  initial begin
    for (int i = 0; i < N; i++) begin
      fork
        automatic int k = i;
        add(k);
        add(k + 10);
      join_none
      fork
        add(i + 100);
      join
    end
    #1;
    `checkd(add_sum, 2 * (3 * (N * (N - 1) / 2) + 110 * N));
  end

  // Test: processes started in a loop share a variable of their parent, and each has its own
  // copy of the fork's variable, also when it waits on a nested fork
  int shared_seen[N];
  int own_seen[N];
  initial begin
    automatic int gen = 0;
    for (int i = 0; i < N; i++) begin
      fork
        automatic int id = i;
        begin
          fork
            #1;
          join
          own_seen[id] = id + 1;
          shared_seen[id] = gen;
        end
      join_none
      gen = i;
    end
    gen = 100;
    #2;
    for (int i = 0; i < N; i++) begin
      `checkd(own_seen[i], i + 1);
      `checkd(shared_seen[i], 100);
    end
  end

  // Test: concurrent calls of a task each share their own variable with the process they start
  int stage_seen[N];
  task automatic stage_after(int idx);
    int stage = 0;
    fork
      begin
        fork
          #1;
          #2;
        join_any
        stage_seen[idx] = stage;
      end
    join_none
    stage = idx + 1;
    #3;
  endtask
  initial begin
    for (int i = 0; i < N; i++) begin
      fork
        automatic int k = i;
        stage_after(k);
      join_none
    end
    #4;
    for (int i = 0; i < N; i++) `checkd(stage_seen[i], i + 1);
  end

  initial begin
    #(20 * N);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
