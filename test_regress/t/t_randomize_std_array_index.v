// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Aditya Shevade
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// A std::randomize() with-clause argument used as an index has no rand
// qualifier of its own, but must still be treated as part of the solve.

// Index into arrays that are not randomized
class StateArrays;
  int unsigned num[];
  function int pick();
    int idx;
    int randomize_result;
    randomize_result = std::randomize(idx) with {
      idx inside {[0 : 2]};
      num[idx] > 0;
    };
    `checkd(randomize_result, 1)
    return idx;
  endfunction
endclass

function automatic int pick_local(int pos);
  bit [14:0] local_q[$] = {15'h0, 15'h0, 15'h0, 15'h0};
  bit [3:0] idx;
  int randomize_result;
  local_q[pos] = 15'h7fff;
  randomize_result = std::randomize(idx) with {local_q[idx] == 15'h7fff;};
  `checkd(randomize_result, 1)
  return int'(idx);
endfunction

module t;
  int unsigned num[] = '{0, 0, 0};
  int unsigned fixed[1:3];

  task automatic check_state_arrays();
    StateArrays arrays = new;
    int idx;
    longint wide_idx;
    bit [38:0] idx39;
    bit signed [4:0] sidx;
    bit [3:0] big[];
    int randomize_result;
    for (int pos = 0; pos < 3; ++pos) begin
      num = '{0, 0, 0};
      num[pos] = 2;
      randomize_result = std::randomize(idx) with {
        idx inside {[0 : 2]};
        num[idx] > 0;
      };
      `checkd(randomize_result, 1)
      `checkd(idx, pos)
      fixed = '{0, 0, 0};
      fixed[pos+1] = 5;
      randomize_result = std::randomize(idx) with {
        idx inside {[1 : 3]};
        fixed[idx] == 5;
      };
      `checkd(randomize_result, 1)
      `checkd(idx, pos + 1)
      // Index wider than 32 bits, with values that would alias 'pos' when truncated
      randomize_result = std::randomize(wide_idx) with {
        wide_idx inside {[-3 : 3], 64'h1_0000_0000 + 64'(pos)};
        num[wide_idx] > 0;
      };
      `checkd(randomize_result, 1)
      `checkd(wide_idx, 64'(pos))
      randomize_result = std::randomize(idx39) with {
        idx39 inside {[0 : 3], 39'h1_0000_0000 + 39'(pos)};
        num[idx39] > 0;
      };
      `checkd(randomize_result, 1)
      `checkd(idx39, 39'(pos))
      arrays.num = num;
      `checkd(arrays.pick(), pos)
      // Negative narrow index, which must not select an element when zero-extended
      big = new[32];
      big[31] = 1;
      big[pos] = 1;
      repeat (4) begin
        randomize_result = std::randomize(sidx) with {
          sidx inside {-5'sd1, 5'(pos)};
          big[sidx] != 0;
        };
        `checkd(randomize_result, 1)
        `checkd(sidx, 5'(pos))
      end
      `checkd(pick_local(pos), pos)
    end
  endtask

  bit [7:0] probe[2];
  bit [7:0] cube[4][2];
  bit [7:0] p0;
  bit [7:0] q[$];
  int i;
  int ok;

  initial begin
    check_state_arrays();

    repeat (30) begin
      ok = std::randomize(
          probe, cube, i
      ) with {
        i inside {[0 : 3]};
        probe == cube[i];
      };
      if (ok != 1) $stop;
      if (probe != cube[i]) $stop;
    end

    repeat (30) begin
      ok = std::randomize(
          p0, cube, i
      ) with {
        i inside {[0 : 3]};
        p0 == cube[i][0];
      };
      if (ok != 1) $stop;
      if (p0 != cube[i][0]) $stop;
    end

    repeat (30) begin
      q = {8'h1, 8'h2, 8'h3, 8'h4};
      ok = std::randomize(
          p0, q, i
      ) with {
        i inside {[0 : 3]};
        p0 == q[i];
      };
      if (ok != 1) $stop;
      if (p0 != q[i]) $stop;
    end

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
