// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2019 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module t;
  class Cls;
    int que[$];

    task push_data(int val);
      que.push_back(val);
    endtask

    function logic ok;
      return '1;
    endfunction
  endclass

  initial begin
    Cls c2[1:0];
    Cls cq[$];

    c2[0] = new();

    c2[0].push_data(20);  // Works

    if (c2[0].que.size() != 1) $stop;

    c2[0].que.push_back(10);  // Unsupported
    if (c2[0].que.size() != 2) $stop;

    // Test there's no side effect warning on iteration
    foreach (cq[i])
    case (cq[i].ok())
      '0: $stop;
      '1: $stop;
    endcase
  end

  // Queue methods on an element of an associative array class member
  typedef struct {int q[$];} rec_t;
  typedef int q_t[$];
  class Store;
    rec_t byId[int];
    q_t qs[string];
    rec_t wild[*];
  endclass
  class Outer;
    Store st;
  endclass

  initial begin
    Store s;
    Outer o;
    s = new;
    o = new;
    o.st = new;
    s.byId[3].q.push_back(4);
    s.byId[3].q.push_front(5);
    s.byId[3].q.insert(1, 6);
    s.byId[3].q.sort();
    `checkd(s.byId[3].q.size(), 3);
    `checkd(s.byId[3].q[0], 4);
    `checkd(s.byId[3].q[2], 6);
    s.qs["a"].push_back(7);
    `checkd(s.qs["a"][0], 7);
    s.wild[5].q.push_back(8);
    `checkd(s.wild[5].q[0], 8);
    o.st.byId[1].q.push_back(9);
    `checkd(o.st.byId[1].q[0], 9);
    `checkd(s.byId.size(), 1);

    $write("*-* All Finished *-*\n");
    $finish;
  end

endmodule
