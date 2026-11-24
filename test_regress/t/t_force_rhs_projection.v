// DESCRIPTION: Verilator: force RHS class-array selection and reactivation
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;
  typedef logic [6:0] word_t;
  class Bag;
    word_t items[4];
  endclass

  Bag bag;
  int idx = 1;
  word_t arg = 0;
  word_t from_member;
  int member_calls = 0;
  function automatic word_t sample_member(word_t x);
    ++member_calls;
    return x + 7'd2;
  endfunction

  word_t q[$];
  word_t from_tail;
  int tail_calls = 0;
  function automatic word_t sample_tail(word_t x);
    ++tail_calls;
    return x + 7'd2;
  endfunction

  task activate_tail();
    force from_tail = sample_tail(arg) + (q.size() != 0 ? q[$] : 7'd7);
  endtask

  initial begin
    bag = new;
    bag.items[1] = 7'd3;
    #1;
    force from_member = sample_member(arg) + bag.items[idx];
    #1;
    if (from_member !== 7'd5 || member_calls != 1) $fatal(1, "Initial member element");
    bag.items[0] = 7'd9;
    #1;
    if (member_calls != 1) $fatal(1, "Unselected member element caused reevaluation");
    bag.items[1] = 7'd8;
    #1;
    if (from_member !== 7'd10 || member_calls != 2) $fatal(1, "Selected member did not update");
    release from_member;
    bag = null;

    activate_tail();
    if (from_tail !== 7'd9 || tail_calls != 1) $fatal(1, "Immediate empty-queue force");
    #1;
    if (tail_calls != 1) $fatal(1, "Activation repeated after settling");
    q.push_back(7'd3);
    #1;
    if (from_tail !== 7'd5 || tail_calls != 2) $fatal(1, "Queue became nonempty");
    q.delete();
    #1;
    if (from_tail !== 7'd9 || tail_calls != 3) $fatal(1, "Queue became empty");
    release from_tail;

    q.push_back(7'd6);
    #1;
    if (from_tail !== 7'd9 || tail_calls != 3) $fatal(1, "Released force kept evaluating");
    activate_tail();
    if (from_tail !== 7'd8 || tail_calls != 4) $fatal(1, "Reactivation did not sample once");
    #1;
    if (from_tail !== 7'd8 || tail_calls != 4) $fatal(1, "Reactivation repeated after settling");
    release from_tail;
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
