// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

package pkg;
  task automatic pkg_tsk();
  endtask
endpackage

module t;
  logic [6:0] a = 0;

  // Blocks and tasks that cannot suspend are never executing when another process disables them
  logic [6:0] b_comb;
  always_comb begin : blk_comb
    b_comb = a + 7'd1;
  end

  function automatic logic [6:0] f_add(input logic [6:0] i, input logic [6:0] n);
    return i + n;
  endfunction
  logic [6:0] b_star;
  always @* begin : blk_star
    b_star = f_add(a, 7'd2);
  end

  logic [6:0] b_task;
  task automatic tsk(input logic [6:0] i);
    b_task = i + 7'd3;
  endtask
  always @* tsk(a);

  logic [6:0] b_void;
  function automatic void f_void(input logic [6:0] i);
    b_void = i + 7'd5;
  endfunction
  always_comb begin : blk_void
    f_void(a);
  end

  // Disables from a task
  task automatic t_dis_comb();
    disable blk_comb;
    disable tsk;
  endtask
  initial #11 t_dis_comb();

  // A task in a package, or a method, may suspend (compile-only: these race the disables)
  int q[$];
  int n_pkg = 0;
  int n_meth = 0;
  initial begin : blk_pkg
    pkg::pkg_tsk();
    n_pkg = 1;
  end
  initial begin : blk_meth
    n_meth = q.size() + 1;
  end
  initial begin
    disable blk_pkg;
    disable blk_meth;
  end

  // A task disabling itself terminates
  int n_self = 0;
  task automatic t_self();
    disable t_self;
    n_self = 1;
  endtask
  initial t_self();

  // Disabling a suspendable block does not make the disabling block suspendable
  logic [6:0] b_dis;
  initial begin : blk_wait
    #1000;
  end
  always_comb begin : blk_dis
    b_dis = a + 7'd4;
    if (a == 7'd127) disable blk_wait;
  end

  // A block calling a task may suspend, so disabling it still terminates it
  int n_call = 0;
  task automatic t_wait();
    #3 n_call = 1;
  endtask
  initial begin : blk_call
    t_wait();
  end
  initial #2 disable blk_call;
  task automatic t_kill();
    disable blk_call;
  endtask
  initial #1 t_kill();

  // Disabling a block kills the processes it forked
  int n_fork = 0;
  initial begin : blk_fork
    fork
      #3 n_fork = 1;
    join_none
  end
  initial #1 disable blk_fork;

  initial begin
    for (int i = 1; i < 20; ++i) begin
      #1 a = 7'(i * 9);
      if (i == 5) begin
        disable blk_comb;
        disable blk_star;
        disable tsk;
        disable blk_dis;
        disable blk_void;
      end
      #1;
      `checkd(b_comb, 7'(i * 9 + 1));
      `checkd(b_star, 7'(i * 9 + 2));
      `checkd(b_task, 7'(i * 9 + 3));
      `checkd(b_dis, 7'(i * 9 + 4));
      `checkd(b_void, 7'(i * 9 + 5));
    end
    `checkd(n_call, 0);
    `checkd(n_fork, 0);
    `checkd(n_self, 0);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
