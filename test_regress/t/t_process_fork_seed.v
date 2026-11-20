// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define checks(gotv,expv) do if ((gotv) != (expv)) begin $write("%%Error: %s:%0d:  got='%s' exp='%s'\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Objects a thread creates are seeded from its RNG, and the random values it
// draws come from it (IEEE 1800-2023 18.14.1), whatever its forked children or
// other processes run in between. Checks compare whole RNG states.

class Rand;
  rand int unsigned m_val;
endclass

// Creates an object on each clock edge. It has no process of its own, so the object is
// seeded from the current process; were it given one, the checks using it would pass
// without testing anything.
module observer (
    input logic clk,
    output bit created
);
  Rand obj;
  always @(posedge clk) begin
    obj = new;
    created = obj != null;
  end
endmodule

// Process that kills a child of a fork that another process joins, which resumes the joiner;
// the joiner then kills this process. Done once this process's RNG is unchanged afterwards.
module kill_by_resumed #(
    parameter bit IN_TASK = 1'b0,
    // Whether to call a function taking the process after the kill
    parameter bit SELF_AFTER = 1'b0
) (
    output bit done
);
  localparam int SEED = 42;

  class Killer;
    // Does not suspend, as waitAfter is false
    static task killChild(process child, bit waitAfter);
      child.kill();
      if (waitAfter) #1;
    endtask
  endclass

  process killer;
  process joinedChild;
  process killerSelf;
  string killerState;
  initial begin : joiner
    fork
      begin
        joinedChild = process::self();
        #10;
      end
    join
    killer.kill();
  end

  initial begin : kills_joined_child
    Rand r;
    int randomize_result;
    #1;
    killer = process::self();
    killer.srandom(SEED);
    killerState = killer.get_randstate();
    if (IN_TASK) Killer::killChild(joinedChild, 1'b0);
    else joinedChild.kill();
    // Statements after the kill should not run (IEEE 1800-2023 9.7); if they do, they must not
    // draw from the killed process
    if (SELF_AFTER) killerSelf = process::self();
    r = new;
    randomize_result = r.randomize();
  end

  initial begin : check
`ifdef VERILATOR
    // Whether the joiner runs within kill() is up to the implementation (IEEE 1800-2023 4.7)
    #2 done = killer.status() == process::KILLED && killer.get_randstate() == killerState;
`else
    #2 done = 1'b1;
`endif
  end
endmodule

// Process that kills a process suspended in a fork..join, directly or inside a task, then
// creates an object. Gives the object's RNG state.
module kill_suspended_joiner #(
    parameter bit IN_TASK = 1'b0
) (
    output string objState
);
  localparam int SEED = 42;

  class Joiner;
    static task joinChild();
      fork
        begin
          process child;
          child = process::self();
          #10;
        end
      join
      // Makes the task take the caller's process
      disable fork;
    endtask
  endclass

  process joiner;
  initial begin : joining
    joiner = process::self();
    if (IN_TASK) Joiner::joinChild();
    else begin
      fork
        begin
          process child;
          child = process::self();
          #10;
        end
      join
    end
  end

  initial begin : kills_joiner
    process p;
    Rand r;
    #1;
    p = process::self();
    p.srandom(SEED);
    joiner.kill();
    r = new;
    objState = r.get_randstate();
  end
endmodule

module t;
  localparam int SEED = 42;
  // Incremented by each case after its last check
  int casesDone = 0;

  // Function that takes the current process, like a part split out of a larger one
  function automatic void takesProcess();
    process p = process::self();
  endfunction

  // States after the parent forks a child, creates an object and draws a value, which must
  // not depend on how the fork joins or what runs before the draws
  typedef enum {
    JOIN,
    JOIN_NONE,
    JOIN_NONE_CALL,
    JOIN_NONE_DELAY
  } fork_e;

  task automatic forkThenDraw(fork_e form, output string objState, output int unsigned drawn,
                              output string procState);
    process p;
    Rand r;
    bit childDone;  // Only gives the child a statement
    p = process::self();
    p.srandom(SEED);
    case (form)
      JOIN: begin
        fork
          childDone = 1'b1;
        join
      end
      JOIN_NONE: begin
        fork
          childDone = 1'b1;
        join_none
      end
      JOIN_NONE_CALL: begin
        fork
          childDone = 1'b1;
        join_none
        takesProcess();
      end
      JOIN_NONE_DELAY: begin
        fork
          #1 childDone = 1'b1;
        join_none
      end
    endcase
    r = new;
    objState = r.get_randstate();
    drawn = $urandom;
    procState = p.get_randstate();
  endtask

  initial begin : parent_after_fork
    string expObj;
    int unsigned expDrawn;
    string expProc;
    string gotObj;
    int unsigned gotDrawn;
    string gotProc;
    forkThenDraw(JOIN, expObj, expDrawn, expProc);
    forkThenDraw(JOIN_NONE, gotObj, gotDrawn, gotProc);
    `checks(gotObj, expObj);
    `checkh(gotDrawn, expDrawn);
    `checks(gotProc, expProc);
    forkThenDraw(JOIN_NONE_CALL, gotObj, gotDrawn, gotProc);
    `checks(gotObj, expObj);
    `checkh(gotDrawn, expDrawn);
    `checks(gotProc, expProc);
    forkThenDraw(JOIN_NONE_DELAY, gotObj, gotDrawn, gotProc);
    `checks(gotObj, expObj);
    `checkh(gotDrawn, expDrawn);
    `checks(gotProc, expProc);
    ++casesDone;
  end

  // State of a second forked child, seeded from the parent after the first
  task automatic secondChildState(bit firstSuspends, output string state);
    process p;
    p = process::self();
    p.srandom(SEED);
    fork
      if (firstSuspends) #1;
      begin
        process second = process::self();
        state = second.get_randstate();
      end
    join
  endtask

  initial begin : second_child
    string expState;
    string gotState;
    secondChildState(1'b0, expState);
    secondChildState(1'b1, gotState);
    `checks(gotState, expState);
    ++casesDone;
  end

  // States after a process kills a child that another process joins, or does not join
  task automatic killThenDraw(bit joined, output string objState, output int unsigned drawn,
                              output string procState);
    process p;
    process child;
    Rand r;
    fork
      if (joined) begin
        fork
          begin
            child = process::self();
            #10;
          end
        join
      end
      else begin
        fork
          begin
            child = process::self();
            #10;
          end
        join_none
      end
    join_none
    #1;
    p = process::self();
    p.srandom(SEED);
    child.kill();
    r = new;
    objState = r.get_randstate();
    drawn = $urandom;
    procState = p.get_randstate();
  endtask

  initial begin : kill_joined
    string expObj;
    int unsigned expDrawn;
    string expProc;
    string gotObj;
    int unsigned gotDrawn;
    string gotProc;
    killThenDraw(1'b0, expObj, expDrawn, expProc);
    killThenDraw(1'b1, gotObj, gotDrawn, gotProc);
    `checks(gotObj, expObj);
    `checkh(gotDrawn, expDrawn);
    `checks(gotProc, expProc);
    ++casesDone;
  end

  // A process killed by a process that its kill resumed does not stay current, whether it
  // kills directly or from a task that returns without suspending
  bit killedDirectDone;
  kill_by_resumed #(.IN_TASK(1'b0)) u_kill_direct (.done(killedDirectDone));
  bit killedInTaskDone;
  kill_by_resumed #(.IN_TASK(1'b1)) u_kill_in_task (.done(killedInTaskDone));
  // Nor does a function taking the process make it current
  bit killedSelfDone;
  kill_by_resumed #(.SELF_AFTER(1'b1)) u_kill_self (.done(killedSelfDone));
  initial begin : killed_not_current
    #3;
    `checkh(killedDirectDone, 1'b1);
    `checkh(killedInTaskDone, 1'b1);
    `checkh(killedSelfDone, 1'b1);
    ++casesDone;
  end

  // A process that kills a process suspended in a task keeps drawing from its own RNG
  string joinerDirectState;
  kill_suspended_joiner #(.IN_TASK(1'b0)) u_joiner_direct (.objState(joinerDirectState));
  string joinerInTaskState;
  kill_suspended_joiner #(.IN_TASK(1'b1)) u_joiner_in_task (.objState(joinerInTaskState));
  initial begin : killer_keeps_current
    #3 `checks(joinerInTaskState, joinerDirectState);
    ++casesDone;
  end

  // A killed process whose suspended calls were destroyed does not stay current for code
  // without a process of its own
  class Waiter;
    static task waitInTask();
      #5;
    endtask
  endclass

  process killedInTask;
  initial begin : killed_in_task
    fork
      begin
        killedInTask = process::self();
        Waiter::waitInTask();
      end
    join_none
    #1 killedInTask.kill();
  end

  logic drawClk = 1'b0;
  bit drawn;
  observer u_observer (
      .clk(drawClk),
      .created(drawn)
  );

  initial begin : no_stale_current
    string killedState;
    // Waits as long as the killed process's call, and queues before it, so the observer runs
    // after that call is destroyed, with no other process resumed in between
    #5 killedState = killedInTask.get_randstate();
    drawClk = 1'b1;
    #1;
    `checkh(killedInTask.status(), process::KILLED);
    `checks(killedInTask.get_randstate(), killedState);
    `checkh(drawn, 1'b1);
    ++casesDone;
  end

  initial begin
    #20;
    `checkh(casesDone, 6);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
