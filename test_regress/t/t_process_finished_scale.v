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
  // 'disable fork' and 'wait fork' must not slow down with the number of finished child
  // processes that are kept alive (by pending delays or by handles)
  localparam int N = 40000;

  class Chain;
    static process procs[$];
    // Each level records its process, forks the next level and finishes
    static task spawn(int depth);
      procs.push_back(process::self());
      if (depth > 0) begin
        fork
          spawn(depth - 1);
        join_none
      end
    endtask
  endclass

  initial begin
    process procs[N];
    int cnt;
    // Timeout idiom: the killed watchdog stays scheduled far in the future
    cnt = 0;
    for (int i = 0; i < N; i++) begin
      fork
        #1;
        #1000000;
      join_any
      disable fork;
      cnt++;
    end
    `checkd($time, 64'(N));
    `checkd(cnt, N);
    // Handles keep finished children alive
    cnt = 0;
    for (int i = 0; i < N; i++) begin
      fork
        automatic int j = i;
        begin
          procs[j] = process::self();
          // Any non-constant delay draws ZERODLY
          // verilator lint_off ZERODLY
          #(j + 1);
          // verilator lint_on ZERODLY
          cnt++;
        end
      join_none
    end
    #(N / 2);
    procs[N - 1].kill();
    wait fork;
    `checkd($time, 64'(2 * N - 1));
    `checkd(cnt, N - 1);
    `checkd(procs[0].status(), process::FINISHED);
    `checkd(procs[N - 1].status(), process::KILLED);
    // A handle keeps a finished process alive whose own child finishes later
    cnt = 0;
    for (int i = 0; i < N; i++) begin
      fork
        automatic int j = i;
        begin
          procs[j] = process::self();
          fork
            #1 cnt++;
          join_none
        end
      join_none
      #2;
      disable fork;
    end
    `checkd(cnt, N);
    `checkd(procs[0].status(), process::FINISHED);
    // Handles keep chains of finished processes alive, then are dropped leaf to root
    repeat (8) begin
      fork
        Chain::spawn(N);
      join_none
      #1;
      `checkd(Chain::procs.size(), N + 1);
      while (Chain::procs.size() > 0) void'(Chain::procs.pop_back());
    end
    // A killed process runs on until it suspends; what it forks is still disabled
    cnt = 0;
    fork
      begin
        process p;
        p = process::self();
        p.kill();
        fork
          #5 cnt++;
        join_none
      end
    join_none
    #1 disable fork;
    #10 `checkd(cnt, 0);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
