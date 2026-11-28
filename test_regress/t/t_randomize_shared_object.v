// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// An object reached through several rand handles is one of the objects randomized as a whole
// (IEEE 1800-2023 18.5.8), so randomized, and its callbacks called (18.6.2), once per call

class Shared;
  randc bit [1:0] r;
  rand bit [7:0] x;
  int pre_count;
  int post_count;
  constraint c_x {x < 8'd100;}
  function void pre_randomize();
    ++pre_count;
  endfunction
  function void post_randomize();
    ++post_count;
  endfunction
endclass

class Pair;
  rand Shared s1;
  rand Shared s2;
endclass

class Triple;
  rand Shared s1;
  rand Shared s2;
  rand Shared s3;
endclass

class Top;
  rand Triple t;
  rand Shared s;
endclass

// Global constraints on the object through one of the handles
class GlobalPair;
  rand Shared s1;
  rand Shared s2;
  constraint c_s1 {s1.x > 8'd10;}
endclass

// Randomizing the object directly from a callback still calls its callbacks
class DirectPair;
  rand Shared s1;
  rand Shared s2;
  int direct_result;
  function void post_randomize();
    direct_result = s1.randomize();
  endfunction
endclass

// A failed randomize() of an object of a rand handle array, called by the pre_randomize() of
// the object holding it, leaves it to be randomized again in the call, which fails too
class FailItem;
  rand bit [3:0] v;
  bit bad;
  constraint c {bad -> v != v;}
endclass

class FailHolder;
  rand FailItem items[$];
  bit call_item;
  int item_ok;
  function void pre_randomize();
    if (call_item) item_ok = items[0].randomize();
  endfunction
endclass

module t;
  initial begin
    automatic Shared sh = new;
    automatic int randomize_result;
    automatic bit [3:0] seen;

    // Two handles: once per call; randc gives a permutation over 4 calls only if so
    begin
      automatic Pair p = new;
      p.s1 = sh;
      p.s2 = sh;
      seen = '0;
      repeat (4) begin
        randomize_result = p.randomize();
        `checkd(randomize_result, 1);
        seen[sh.r] = 1'b1;
      end
      `checkd(seen, 4'hf);
      `checkd(sh.pre_count, 4);
      `checkd(sh.post_count, 4);

      // The object stays among those randomized through the other handle
      p.s1.rand_mode(0);
      seen = '0;
      repeat (4) begin
        randomize_result = p.randomize();
        `checkd(randomize_result, 1);
        seen[sh.r] = 1'b1;
      end
      `checkd(seen, 4'hf);
      `checkd(sh.pre_count, 8);
      `checkd(sh.post_count, 8);
    end

    // Three handles, and a handle of the object holding them
    begin
      automatic Triple tr = new;
      automatic Top top = new;
      tr.s1 = sh;
      tr.s2 = sh;
      tr.s3 = sh;
      randomize_result = tr.randomize();
      `checkd(randomize_result, 1);
      `checkd(sh.pre_count, 9);
      `checkd(sh.post_count, 9);
      top.t = tr;
      top.s = sh;
      seen = '0;
      repeat (4) begin
        randomize_result = top.randomize();
        `checkd(randomize_result, 1);
        seen[sh.r] = 1'b1;
      end
      `checkd(seen, 4'hf);
      `checkd(sh.pre_count, 13);
      `checkd(sh.post_count, 13);
    end

    begin
      automatic GlobalPair gp = new;
      gp.s1 = sh;
      gp.s2 = sh;
      randomize_result = gp.randomize();
      `checkd(randomize_result, 1);
      `checkd(sh.x > 8'd10, 1'b1);
      `checkd(sh.pre_count, 14);
      `checkd(sh.post_count, 14);
    end

    begin
      automatic DirectPair dp = new;
      dp.s1 = sh;
      dp.s2 = sh;
      randomize_result = dp.randomize();
      `checkd(randomize_result, 1);
      `checkd(dp.direct_result, 1);
      `checkd(sh.pre_count, 16);
      `checkd(sh.post_count, 16);
    end

    begin
      automatic FailHolder fh = new;
      automatic FailItem fi = new;
      automatic int ok;
      fh.items.push_back(fi);
      fi.bad = 1'b1;
      fh.call_item = 1'b1;
      ok = fh.randomize();
      `checkd(fh.item_ok, 0);
      `checkd(ok, 0);
      fi.bad = 1'b0;
      ok = fh.randomize();
      `checkd(fh.item_ok, 1);
      `checkd(ok, 1);
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
