// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__, `__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// A scalar solve-before session still sends a state-array constructor.
// A rand_mode(0) associative array is held with a constant-array default for missing keys
class PhaseState;
  rand logic [3:0] state_arr[int];
  rand int unsigned idx;
  rand bit [3:0] v;
  constraint c {
    idx == 1;
    v == state_arr[idx];
    solve idx before v;
  }
  function new();
    state_arr[0] = 0;
    state_arr[1] = 0;
    state_arr.rand_mode(0);
  endfunction
endclass

// A state-array constructor in a soft constraint still needs ALL during phased solving.
class PhaseSoftOnly;
  rand logic [4:0] state_arr[int];
  rand int unsigned soft_idx;
  rand bit [4:0] soft_v;
  constraint c {
    soft_idx == 1;
    soft soft_v == state_arr[soft_idx];
    solve soft_idx before soft_v;
  }
  function new();
    state_arr[0] = 0;
    state_arr[1] = 0;
    state_arr.rand_mode(0);
  endfunction
endclass

class PhaseScalar;
  rand bit [2:0] plain_idx;
  rand bit [8:0] plain_v;
  constraint c {
    plain_idx inside {[1 : 3]};
    plain_v == 9'(plain_idx) + 9'h101;
    solve plain_idx before plain_v;
  }
endclass

// A state array read through a random index needs no constant array
class SamplerState;
  logic [6:0] state_arr[2] = '{7'h12, 7'h34};
  rand int unsigned idx;
  rand bit [6:0] v;
  constraint c {
    idx < 2;
    v == state_arr[idx];
  }
endclass

module t;
  initial begin
    automatic PhaseState obj = new;
    automatic SamplerState sample_obj = new;
    automatic PhaseSoftOnly soft_obj = new;
    automatic PhaseScalar plain_obj = new;
    for (int step = 0; step < 4; ++step) begin
      int ok;
      obj.state_arr[0] = 4'(step);
      obj.state_arr[1] = 4'h5 ^ {4{step[0]}} ^ 4'(step >> 1);
      ok = obj.randomize();
      `checkd(ok, 1);
      `checkd(obj.idx, 1);
      `checkd(obj.v, obj.state_arr[1]);
      `checkd(obj.state_arr[0], 4'(step));
      `checkd(obj.state_arr[1], 4'h5 ^ {4{step[0]}} ^ 4'(step >> 1));
    end
    for (int step = 0; step < 16; ++step) begin
      int ok;
      ok = sample_obj.randomize();
      `checkd(ok, 1);
      `checkd(sample_obj.idx < 2, 1);
      `checkd(sample_obj.v, sample_obj.state_arr[sample_obj.idx]);
      `checkd(sample_obj.state_arr[0], 7'h12);
      `checkd(sample_obj.state_arr[1], 7'h34);
    end
    for (int step = 0; step < 4; ++step) begin
      int ok;
      soft_obj.state_arr[0] = 5'(step);
      soft_obj.state_arr[1] = 5'h15 ^ 5'(step);
      ok = soft_obj.randomize();
      `checkd(ok, 1);
      `checkd(soft_obj.soft_idx, 1);
      `checkd(soft_obj.soft_v, soft_obj.state_arr[1]);
      `checkd(soft_obj.state_arr[0], 5'(step));
      `checkd(soft_obj.state_arr[1], 5'h15 ^ 5'(step));
    end
    for (int step = 0; step < 4; ++step) begin
      int ok;
      ok = plain_obj.randomize();
      `checkd(ok, 1);
      `checkd(plain_obj.plain_idx inside {[1 : 3]}, 1);
      `checkd(plain_obj.plain_v, 9'(plain_obj.plain_idx) + 9'h101);
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
