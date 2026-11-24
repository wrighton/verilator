// DESCRIPTION: Verilator: force RHS projections of dynamic containers
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;
  typedef logic [6:0] word_t;
  word_t q[$];
  word_t da[];
  word_t aa[int];
  word_t arg = 0;
  wire [6:0] tail = 7'd33;
  word_t queue_size, array_size, assoc_size;
  int calls[4];

  function automatic word_t sample_word(int site, word_t x);
    ++calls[site];
    return x + 7'd2;
  endfunction

  initial begin
    q = '{7'd1, 7'd2};
    da = new[2];
    aa[2] = 7'd1;
    aa[5] = 7'd2;
    #1;
    force tail = sample_word(0, arg) + q[$];
    force queue_size = sample_word(1, arg) + word_t'(q.size());
    force array_size = sample_word(2, arg) + word_t'(da.size());
    force assoc_size = sample_word(3, arg) + word_t'(aa.num());
    #1;
    if ({tail, queue_size, array_size, assoc_size} !== {4{7'd4}} || calls != '{1, 1, 1, 1})
      $fatal(1, "Initial projection values or duplicate activation evaluations");

    q[0] = 7'd20;
    da[0] = 7'd20;
    aa[2] = 7'd20;
    #1;
    if (calls != '{1, 1, 1, 1}) $fatal(1, "Unchanged projections were re-evaluated");

    q[1] = 7'd18;
    #1;
    if (tail !== 7'd20 || calls != '{2, 1, 1, 1}) $fatal(1, "Queue back element did not update");

    q.push_back(7'd19);
    da = new[3] (da);
    aa[8] = 7'd20;
    #1;
    if ({tail, queue_size, array_size, assoc_size} !== {7'd21, 7'd5, 7'd5, 7'd5} || calls !=
        '{3, 2, 2, 2}
        )
      $fatal(1, "Changed container projections did not update");

    release tail;
    release queue_size;
    release array_size;
    release assoc_size;
    arg = 7'd9;
    q.delete();
    da.delete();
    aa.delete();
    #1;
    if ({tail, queue_size, array_size, assoc_size} !== {7'd33, 7'd5, 7'd5, 7'd5} || calls !=
        '{3, 2, 2, 2}
        )
      $fatal(1, "Released forces did not stop evaluating");
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
