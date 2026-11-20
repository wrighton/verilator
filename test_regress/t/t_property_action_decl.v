// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Multi-cycle assertion action blocks that declare variables run as often as
// the same actions without declarations, and all executions of an action share
// its static variables.

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

  // Failures of an implication with a local variable, from a named block
  int imp_fails = 0;
  int imp_decl_fails = 0;
  int imp_decl_count = 0;

  property p_imp;
    bit [7:0] x;
    @(posedge clk) (a, x = lfsr) |-> ##2 (b && lfsr[7:2] == x[5:0]);
  endproperty

  assert property (p_imp)
  else imp_fails++;

  assert property (p_imp)
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
  int decl_pass_count = 0;
  int decl_pass_fails = 0;
  int imp_passes = 0;
  int imp_decl_passes = 0;
  int imp_decl_pass_count = 0;

  assert property (@(posedge clk) a ##[1:3] b ##1 c) passes++;
  else pass_fails++;

  assert property (@(posedge clk) a ##[1:3] b ##1 c) begin
    int count;
    ++count;
    decl_passes++;
    decl_pass_count = count;
  end
  else decl_pass_fails++;

  assert property (@(posedge clk) a |-> ##1 1) imp_passes++;

  assert property (@(posedge clk) a |-> ##1 1) begin
    int count;
    ++count;
    imp_decl_passes++;
    imp_decl_pass_count = count;
  end

  // Each pass forks a process with its own automatic variable, alive across later passes
  int fork_starts = 0;
  int fork_ends = 0;
  bit [63:0] fork_seen = 0;

  assert property (@(posedge clk) a |-> ##1 1)
    fork
      automatic int x = fork_starts++;
      begin
        #25;
        fork_seen[x] = 1'b1;
        fork_ends++;
      end
    join_none

  // A hierarchical reference from an action of an assertion in a generate block
  int gen_fails = 0;
  int gen_decl_count = 0;
  int gen_child_seen = 0;
  int gen_sibling_seen = 0;

  if (1) begin : gen
    assert property (@(posedge clk) a ##[1:3] b ##1 c)
    else begin : gen_action
      static int count = 0;
      ++count;
      gen_action.count++;
      gen_decl_count = gen_action.count;
      t.gen_fails++;
      begin : child
        static int slot = 0;
        ++slot;
      end
      // Downward, and from a sibling block
      gen_child_seen = child.slot;
      begin : sibling
        gen_sibling_seen = child.slot;
      end
    end
  end

  // A downward reference from an unnamed action
  int unnamed_seen = 0;

  if (1) begin : unnamed_gen
    assert property (@(posedge clk) a ##[1:3] b ##1 c)
    else begin
      begin : child
        static int slot = 0;
        ++slot;
      end
      unnamed_seen = child.slot;
    end
  end

  // Covers, without --coverage-user not collected, so their actions have no effect
  int cover_inits = 0;
  int cover_runs = 0;

  function int cover_first_count();
    ++cover_inits;
    return 10;
  endfunction

  cover property (@(posedge clk) s_eventually b) begin
    static int count = cover_first_count();
    ++count;
    cover_runs++;
  end
  cover property (@(posedge clk) b until c) begin
    int count;
    count = 1;
    cover_runs += count;
  end
`ifndef T_COVER_COLLECTED
  // Every attempt is still pending at the end of simulation, where cover_late holds
  wire cover_late = cyc == 60;
  cover property (@(posedge clk) s_eventually cover_late) begin
    int count;
    count = 1;
    `checkd(count, 0);
  end
`endif

  // A reference through an instance named like a block of the action
  t_payload u ();
  int payload_seen = 0;
  int payload_calls = 0;

  if (1) begin : payload_gen
    assert property (@(posedge clk) a ##[1:3] b ##1 c)
    else begin : payload_action
      payload_seen = u.payload;
      begin : decoy
        begin : u
          payload_calls++;
        end
      end
    end
  end

  // A hierarchical reference through another instance keeps selecting that instance
  int xmr_seen_a;
  int xmr_seen_b;
  int xmr_seen_up_a;
  int xmr_seen_up_b;

  t_xmr_worker xmr_a (
      .clk(clk),
      .value(37),
      .seen(xmr_seen_a),
      .seen_up(xmr_seen_up_a)
  );
  t_xmr_worker xmr_b (
      .clk(clk),
      .value(91),
      .seen(xmr_seen_b),
      .seen_up(xmr_seen_up_b)
  );

  initial begin
    repeat (60) @(negedge clk);
    `checkd(fails > 0, 1'b1);
    `checkd(decl_fails, fails);
    `checkd(decl_count, 10 + fails);
    `checkd(inits, 1);
    `checkd(imp_fails > 0, 1'b1);
    `checkd(imp_decl_fails, imp_fails);
    `checkd(imp_decl_count, imp_fails);
    `checkd(passes > 0, 1'b1);
    `checkd(decl_passes, passes);
    `checkd(decl_pass_count, passes);
    `checkd(pass_fails, fails);
    `checkd(decl_pass_fails, fails);
    `checkd(imp_passes > 0, 1'b1);
    `checkd(imp_decl_passes, imp_passes);
    `checkd(imp_decl_pass_count, imp_passes);
    `checkd(fork_starts, imp_passes);
    `checkd(fork_ends > 0, 1'b1);
    `checkd($countones(fork_seen), fork_ends);
    `checkd(gen_decl_count, 2 * fails);
    `checkd(gen_fails, fails);
    `checkd(gen_child_seen, fails);
    `checkd(gen_sibling_seen, fails);
    `checkd(unnamed_seen, fails);
`ifdef T_COVER_COLLECTED
    `checkd(cover_inits, 1);
    `checkd(cover_runs > 0, 1'b1);
`else
    `checkd(cover_inits, 0);
    `checkd(cover_runs, 0);
`endif
    `checkd(xmr_seen_a, 37);
    `checkd(xmr_seen_b, 37);
    `checkd(xmr_seen_up_a, 37);
    `checkd(xmr_seen_up_b, 37);
    `checkd(payload_seen, 37);
    `checkd(payload_calls, fails);
    done = 1;
    $finish;
  end

  // End of simulation failures share the static variables of the earlier ones
  bit [1:0] eos_ran = 0;

  task eos_finish(int bit_index);
    `checkd(eos_ran[bit_index], 1'b0);
    eos_ran[bit_index] = 1'b1;
    if (eos_ran == 2'b11) $write("*-* All Finished *-*\n");
  endtask

  // A strong property still pending
  int always_fails = 0;
  int always_eos_fails = 0;

  assert property (@(posedge clk) s_always [1:3] b)
  else if (!done) always_fails++;

  assert property (@(posedge clk) s_always [1:3] b)
  else begin
    static int count = 0;
    ++count;
    if (done) begin
      ++always_eos_fails;
      `checkd(always_fails > 0, 1'b1);
      `checkd(count, always_fails + always_eos_fails);
      if (always_eos_fails == 1) eos_finish(0);
    end
  end

  // Attempts of s_until still pending, as hold stays true and stop never comes
  wire hold = cyc % 7 != 3 || cyc > 50;
  wire stop = cyc > 1000;
  int until_fails = 0;
  int until_eos_fails = 0;

  assert property (@(posedge clk) hold s_until stop)
  else if (!done) until_fails++;

  assert property (@(posedge clk) hold s_until stop)
  else begin
    static int count = 0;
    ++count;
    if (done) begin
      ++until_eos_fails;
      `checkd(until_fails > 0, 1'b1);
      `checkd(count, until_fails + until_eos_fails);
      if (until_eos_fails == 1) eos_finish(1);
    end
  end

endmodule

module t_xmr_worker (
    input bit clk,
    input int value,
    output int seen,
    output int seen_up
);

  if (1) begin : g
    assert property (@(posedge clk) 1'b1 ##[1:2] 1'b0)
    else begin : act
      static int slot = 0;
      slot = value;
      seen = $root.t.xmr_a.g.act.slot;
      // Upward through instance xmr_a, not through the block of that name below
      seen_up = xmr_a.g.act.slot;
      begin : decoy
        begin : xmr_a
          seen_up += 0;
        end
      end
    end
  end

endmodule

module t_payload;
  int payload = 37;
endmodule
