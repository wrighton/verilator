// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0x exp=%0x (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Subroutine call match items run at each match of their single-cycle sequence
// (IEEE 1800-2023 16.11)
module t (
    input clk
);

  int cyc;
  reg [63:0] crc;

  wire a = crc[0];
  wire b = crc[4];
  wire c = crc[8];
  wire [3:0] v = crc[15:12];

  default clocking @(posedge clk);
  endclocking

  int n_ant = 0, n_cons = 0, n_top = 0, n_seq = 0, n_first = 0, n_second = 0;
  int sum_v = 0, n_cons_fail = 0, n_top_fail = 0;
  int exp_ticks = 0, exp_a = 0, exp_ac = 0, exp_sum_v = 0;

  // A task and void functions with side effects on module variables
  task inc_ant;
    n_ant++;
  endtask
  function void inc(int which);
    case (which)
      1: n_cons++;
      2: n_top++;
      3: n_seq++;
      4: n_first++;
      default: n_second += n_first;
    endcase
  endfunction
  function void add(int x);
    sum_v += x;
  endfunction

  sequence s_call;
    (a, inc(3));
  endsequence

  // Antecedent: runs whenever a matches, whether or not the consequent holds
  assert property ((a, inc_ant()) |-> 1);
  // Consequent: runs only when c matches, so not on a failure
  assert property (a |-> (c, inc(1), add(int'(v))))
  else n_cons_fail++;
  // Whole property, a sequence instance, and calls in order
  assert property ((a, inc(2)))
  else n_top_fail++;
  assert property (s_call |-> 1);
  assert property ((a, inc(4), inc(5)) |-> 1);

  always @(posedge clk) begin
    exp_ticks <= exp_ticks + 1;
    if (a) exp_a <= exp_a + 1;
    if (a && c) begin
      exp_ac <= exp_ac + 1;
      exp_sum_v <= exp_sum_v + int'(v);
    end
  end

  // Stimulus on negedge so properties sample stable values
  always @(negedge clk) begin
`ifdef TEST_VERBOSE
    $write("[%0t] cyc==%0d crc=%x a=%b b=%b c=%b\n", $time, cyc, crc, a, b, c);
`endif
    cyc <= cyc + 1;
    crc <= {crc[62:0], crc[63] ^ crc[2] ^ crc[0]};
    if (cyc == 0) begin
      crc <= 64'h5aef0c8d_d70a4497;
    end
    else if (cyc == 99) begin
      `checkh(crc, 64'hc77bb9b3784ea091);
      `checkd(n_ant, exp_a);
      `checkd(n_cons, exp_ac);
      `checkd(sum_v, exp_sum_v);
      `checkd(n_cons_fail, exp_a - exp_ac);
      `checkd(n_top, exp_a);
      `checkd(n_top_fail, exp_ticks - exp_a);
      `checkd(n_seq, exp_a);
      `checkd(n_first, exp_a);
      `checkd(n_second, exp_a * (exp_a + 1) / 2);
      `checkd(exp_a, 49);
      `checkd(exp_ac, 23);
      `checkd(exp_sum_v, 211);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
