// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// A named begin block that contains a fork still has to behave like a normal
// named block when it disables itself: execution resumes after the block, so
// statements after the disable inside the block must not run. All activity
// enabled within the block, including forked child processes, must terminate.

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module t;

  bit after_disable = 1'b0;
  bit after_disable_fork = 1'b0;
  bit disable_fork_survived = 1'b0;
  bit fork_survived = 1'b0;

  initial begin : blk
    fork
      begin
        #5;
        fork_survived = 1'b1;
      end
    join_none
    #1;
    disable blk;
    after_disable = 1'b1;
  end

  // A named fork disabled after join_none has no active enclosing fork branch.
  initial begin
    fork : fork_blk
      begin
        #5;
        disable_fork_survived = 1'b1;
      end
    join_none
    #1;
    disable fork_blk;
    after_disable_fork = 1'b1;
  end

  // Self-disable of a loop body containing a fork, with a break out of the loop
  int loop_cnt = 0;
  initial begin
    while (1) begin : loop_blk
      fork
        #1 loop_cnt++;
      join
      if (loop_cnt > 2) break;
      disable loop_blk;
      loop_cnt += 10;
    end
    `checkd(loop_cnt, 3);
  end

  // Disable from a fork branch, with break and continue out of the block
  int branch_cnt = 0;
  initial begin
    for (int i = 0; i < 5; i++) begin : branch_blk
      if (i == 3) break;
      fork
        begin
          #1 branch_cnt++;
          if (i == 0) disable branch_blk;
        end
      join
      if (i == 1) continue;
      branch_cnt += 10;
    end
    `checkd(branch_cnt, 13);
  end

  // Disable from a fork branch, with return out of the task
  int task_cnt = 0;
  task automatic task_loop();
    for (int i = 0; i < 3; i++) begin : task_blk
      fork
        begin
          #1 task_cnt++;
          if (i == 0) disable task_blk;
        end
      join
      if (i == 1) return;
      task_cnt += 10;
    end
    task_cnt += 100;
  endtask
  initial begin
    task_loop();
    `checkd(task_cnt, 2);
  end

  // Disable of nested blocks from a fork branch
  int nested_cnt = 0;
  initial begin
    for (int i = 0; i < 3; i++) begin : outer_blk
      begin : inner_blk
        fork
          begin
            #1 nested_cnt++;
            if (i == 0) disable inner_blk;
            if (i == 1) disable outer_blk;
          end
        join
        if (i == 2) break;
        nested_cnt += 10;
      end
      nested_cnt += 100;
    end
    `checkd(nested_cnt, 103);
  end

  initial begin
    #10;
    `checkd(after_disable, 1'b0);
    `checkd(after_disable_fork, 1'b1);
    `checkd(disable_fork_survived, 1'b0);
    `checkd(fork_survived, 1'b0);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
