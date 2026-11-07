// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Kristof Marien
// SPDX-License-Identifier: CC0-1.0

// randc cycles (IEEE 1800-2023 18.4.2) continue across randomize() with calls

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// With a class constraint
class RandcOwn;
  randc bit [1:0] x;
  constraint c {x != 0;}
endclass

// Without class constraints
class RandcNone;
  randc bit [1:0] x;
endclass

// The class constraint and randc variable are inherited
class RandcDerived extends RandcOwn;
  rand bit [3:0] y;
endclass

// A resize of an array with a name starting like the randc variable's does not
// restart its cycle
class RandcPrefix;
  randc bit [1:0] q1;
  rand bit [7:0] q[];
  constraint c {
    q1 != 0;
    foreach (q[i]) q[i] < 8'd10;
  }
endclass

// Without randc variables, so without randc cycles to keep
class RandNone;
  rand bit [3:0] y;
endclass

// A randc variable reached through a rand handle, without class constraints
class RandcLeaf;
  randc bit [1:0] x;
endclass

class RandcTop;
  rand RandcLeaf h;
  function new();
    h = new;
  endfunction
endclass

// A randc variable inherited, without class constraints
class RandcLeafDerived extends RandcLeaf;
  rand bit [3:0] y;
endclass

// A cycle of rand handles, with a randc variable
typedef class RandcPong;
class RandcPing;
  randc bit [1:0] x;
  rand RandcPong pong;
endclass

class RandcPong;
  rand RandcPing ping;
endclass

// A cycle of rand handles, without a randc variable
typedef class RandLoopB;
class RandLoopA;
  rand bit [3:0] y;
  rand RandLoopB b;
endclass

class RandLoopB;
  rand RandLoopA a;
endclass

// Rand handles reaching no randc variable
class RandChainC;
  rand bit [3:0] y;
endclass

class RandChainB;
  rand RandChainC h;
  function new();
    h = new;
  endfunction
endclass

class RandChainA;
  rand RandChainB h;
  function new();
    h = new;
  endfunction
endclass

module t;
  initial begin
    automatic RandcOwn own = new;
    automatic RandcNone none = new;
    automatic RandcDerived derived = new;
    automatic RandNone rand_none = new;
    automatic RandcPrefix prefix = new;
    automatic RandcTop top = new;
    automatic RandChainA chain = new;
    automatic RandcLeafDerived leaf_derived = new;
    automatic RandcPing ping = new;
    automatic RandcPong pong = new;
    automatic RandLoopA loop = new;
    automatic int randomize_result;
    for (int trial = 0; trial < 4; ++trial) begin
      // Values seen in this cycle
      automatic bit [3:0] own_seen = 0;
      automatic bit [3:0] none_seen = 0;
      automatic bit [3:0] derived_seen = 0;
      automatic bit [3:0] prefix_seen = 0;
      automatic bit [3:0] top_seen = 0;
      automatic bit [3:0] leaf_derived_seen = 0;
      automatic bit [3:0] ping_seen = 0;
      for (int i = 0; i < 3; ++i) begin
        randomize_result = own.randomize() with {x != 3 || x == 3;};
        `checkd(randomize_result, 1);
        `checkd(own.x == 0, 0);
        `checkd(own_seen[own.x], 0);
        own_seen[own.x] = 1;
        // A failed call does not use up a value
        randomize_result = own.randomize() with {x == 0;};
        `checkd(randomize_result, 0);

        randomize_result = none.randomize() with {x != 2'd0;};
        `checkd(randomize_result, 1);
        `checkd(none.x == 0, 0);
        `checkd(none_seen[none.x], 0);
        none_seen[none.x] = 1;

        // Alternating with randomize() without with, as the with does not constrain x
        if (i % 2 == 0) begin
          randomize_result = derived.randomize() with {y < 4'd5;};
          `checkd(derived.y < 4'd5, 1);
        end
        else begin
          randomize_result = derived.randomize();
        end
        `checkd(randomize_result, 1);
        `checkd(derived.x == 0, 0);
        `checkd(derived_seen[derived.x], 0);
        derived_seen[derived.x] = 1;

        prefix.q = new[i % 2 == 0 ? 12 : 5];
        randomize_result = prefix.randomize() with {foreach (q[k]) q[k] != 8'd11;};
        `checkd(randomize_result, 1);
        `checkd(prefix.q1 == 0, 0);
        `checkd(prefix_seen[prefix.q1], 0);
        prefix_seen[prefix.q1] = 1;

        randomize_result = top.randomize() with {h.x != 0;};
        `checkd(randomize_result, 1);
        `checkd(top.h.x == 0, 0);
        `checkd(top_seen[top.h.x], 0);
        top_seen[top.h.x] = 1;

        randomize_result = leaf_derived.randomize() with {x != 0;};
        `checkd(randomize_result, 1);
        `checkd(leaf_derived.x == 0, 0);
        `checkd(leaf_derived_seen[leaf_derived.x], 0);
        leaf_derived_seen[leaf_derived.x] = 1;

        // Through the other class of the cycle
        pong.ping = ping;
        randomize_result = pong.randomize() with {ping.x != 0;};
        `checkd(randomize_result, 1);
        `checkd(ping.x == 0, 0);
        `checkd(ping_seen[ping.x], 0);
        ping_seen[ping.x] = 1;

        randomize_result = loop.randomize() with {y < 4'd5;};
        `checkd(randomize_result, 1);
        `checkd(loop.y < 4'd5, 1);

        randomize_result = chain.randomize() with {h.h.y < 4'd5;};
        `checkd(randomize_result, 1);
        `checkd(chain.h.h.y < 4'd5, 1);
        randomize_result = chain.h.randomize() with {h.y > 4'd9;};
        `checkd(randomize_result, 1);
        `checkd(chain.h.h.y > 4'd9, 1);

        randomize_result = rand_none.randomize() with {y < 4'd5;};
        `checkd(randomize_result, 1);
        `checkd(rand_none.y < 4'd5, 1);
        randomize_result = rand_none.randomize() with {y > 4'd9;};
        `checkd(randomize_result, 1);
        `checkd(rand_none.y > 4'd9, 1);
      end
    end
    // A randc variable with rand_mode off is a state variable
    derived.x.rand_mode(0);
    begin
      automatic bit [1:0] x = derived.x;
      randomize_result = derived.randomize() with {y < 4'd5;};
      `checkd(randomize_result, 1);
      `checkd(derived.x, x);
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
