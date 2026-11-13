// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// size() of a non-random array reached through an array element in randomize() with is a state
// value

class Item;
  int q[$];
endclass

class Holder;
  rand int x;
  Item items[$];
  rand Item ritems[2];
endclass

class Caller;
  // The object randomized is an argument, so it is not 'this'
  function int randomize_in(Holder h, int j);
    return h.randomize() with {
      if (h.items[j].q.size() > 0) {
        h.x inside {h.items[j].q};
      }
    };
  endfunction
endclass

module t;
  initial begin
    automatic Holder h = new;
    int randomize_result;
    for (int i = 0; i < 3; ++i) begin
      automatic Item it = new;
      repeat (i + 2) it.q.push_back(i);
      h.items.push_back(it);
    end
    foreach (h.ritems[i]) begin
      h.ritems[i] = new;
      repeat (i + 7) h.ritems[i].q.push_back(i);
    end
    for (int j = 0; j < 3; ++j) begin
      randomize_result = h.randomize() with {x == items[j].q.size();};
      `checkd(randomize_result, 1);
      `checkd(h.x, j + 2);
      `checkd(h.items[j].q.size(), j + 2);
    end
    for (int j = 0; j < 2; ++j) begin
      randomize_result = h.randomize() with {x == ritems[j].q.size();};
      `checkd(randomize_result, 1);
      `checkd(h.x, j + 7);
    end
    begin
      automatic Caller c = new;
      foreach (h.items[2].q[i]) h.items[2].q[i] = i * 3 + 1;
      repeat (10) begin
        `checkd(c.randomize_in(h, 2), 1);
        `checkd(h.x % 3, 1);
        if (h.x < 1 || h.x > 10) `stop;
        `checkd(h.items[2].q.size(), 4);
      end
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
