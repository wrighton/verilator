// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Multi-cycle assertion action blocks that declare variables run once per
// attempt, like the same actions without declarations, sharing their static
// variables between all executions.

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define checks(gotv,expv) do if ((gotv) != (expv)) begin $write("%%Error: %s:%0d:  got='%s' exp='%s'\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module t;

  bit clk = 0;
  always #5 clk = ~clk;

  int cyc = 0;
  always @(posedge clk) cyc <= cyc + 1;

  bit [7:0] lfsr = 8'h5a;
  always @(posedge clk) lfsr <= {lfsr[6:0], lfsr[7] ^ lfsr[5] ^ lfsr[4] ^ lfsr[3]};

  wire a = lfsr[0];
  wire b = lfsr[3];
  wire c = lfsr[5];

  // Set just before $finish, so end of simulation actions can tell
  bit done = 0;

  // Failures, including attempts failing in the same clock
  int fails = 0;
  int decl_fails = 0;
  int decl_count = 0;
  int inits;

  function int first_count();
    ++inits;
    return 10;
  endfunction

  assert property (@(posedge clk) a ##[1:3] b ##1 c)
  else fails++;

  assert property (@(posedge clk) a ##[1:3] b ##1 c)
  else begin : fail_action
    typedef int count_t;
    static count_t count = first_count();
    automatic int once = 0;
    ++count;
    ++once;
    `checkd(once, 1);
    `checks($sformatf("%m"), "t.fail_action");
    decl_fails++;
    decl_count = count;
  end

  // Failures of an implication, from a named block
  int imp_fails = 0;
  int imp_decl_fails = 0;
  int imp_decl_count = 0;

  assert property (@(posedge clk) a |-> ##2 b)
  else imp_fails++;

  assert property (@(posedge clk) a |-> ##2 b)
  else begin : imp_action
    int count;
    ++count;
    imp_decl_fails++;
    imp_decl_count = count;
  end

  // Passes
  int passes = 0;
  int pass_fails = 0;
  int decl_passes = 0;
  int decl_pass_fails = 0;
  int imp_passes = 0;
  int imp_decl_passes = 0;

  assert property (@(posedge clk) a ##[1:3] b ##1 c) passes++;
  else pass_fails++;

  assert property (@(posedge clk) a ##[1:3] b ##1 c) begin
    int one;
    one = 1;
    decl_passes += one;
  end
  else decl_pass_fails++;

  assert property (@(posedge clk) a |-> ##1 1) imp_passes++;

  assert property (@(posedge clk) a |-> ##1 1) begin
    int one;
    one = 1;
    imp_decl_passes += one;
  end

  // Each pass forks a process with its own automatic variable
  int fork_hits = 0;

  assert property (@(posedge clk) a |-> ##1 1)
    fork
      automatic int x = 37;
      begin
        `checkd(x, 37);
        fork_hits++;
      end
    join_none

  initial begin
    repeat (60) @(negedge clk);
    `checkd(fails, 38);
    `checkd(decl_fails, fails);
    `checkd(decl_count, 10 + fails);
    `checkd(inits, 1);
    `checkd(imp_fails, 16);
    `checkd(imp_decl_fails, imp_fails);
    `checkd(imp_decl_count, imp_fails);
    `checkd(passes, 15);
    `checkd(decl_passes, passes);
    `checkd(pass_fails, fails);
    `checkd(decl_pass_fails, fails);
    `checkd(imp_passes, 59);
    `checkd(imp_decl_passes, imp_passes);
    `checkd(fork_hits, imp_passes);
    done = 1;
    $finish;
  end

  // End of simulation actions share the static variables of the others
  bit [1:0] eos_ran = 0;

  task eos_finish(int bit_index);
    `checkd(eos_ran[bit_index], 1'b0);
    eos_ran[bit_index] = 1'b1;
    if (eos_ran == 2'b11) $write("*-* All Finished *-*\n");
  endtask

  // A strong property still pending fails
  int always_fails = 0;

  assert property (@(posedge clk) s_always [1:3] b)
  else if (!done) always_fails++;

  assert property (@(posedge clk) s_always [1:3] b)
  else begin
    static int count = 0;
    ++count;
    if (done) begin
      `checkd(count, always_fails + 1);
      eos_finish(0);
    end
  end

  // Attempts still pending pass, as ev holds at the end
  wire ev = cyc % 4 == 0;
  int ev_passes = 0;
  int ev_eos_passes = 0;

  assert property (@(posedge clk) s_eventually ev)
    if (!done) ev_passes++;

  assert property (@(posedge clk) s_eventually ev) begin
    static int count = 0;
    ++count;
    if (done) begin
      ++ev_eos_passes;
      `checkd(count, ev_passes + ev_eos_passes);
      if (ev_eos_passes == 1) eos_finish(1);
    end
  end

endmodule
