// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

// A named property whose body is 'always p', instanced as a whole property
// (IEEE 1800-2023 16.12.11). Each instance is compared with the same assertion
// written out, whose attempts with a boolean p fail once per attempt, as a model
// of the attempts gives.
module t (
  input clk
);
  int unsigned crc = 32'h1;
  logic a, b, c;
  int cyc = 0;
  // Attempts of 'always a', 'always b' and 'disable iff (c) always a' started since their previous
  // failure, and their failures
  int live_a = 0, live_b = 0, live_dis = 0, exp_a = 0, exp_b = 0, exp_dis = 0;
  // Attempts of 'c |-> always a', 'c |=> always a' and 'c |-> always b' pending since their
  // previous failure, and the ticks they fail on
  int live_ia = 0, live_na = 0, live_ib = 0, ticks_ia = 0, ticks_na = 0, ticks_ib = 0;

  always @(posedge clk) begin
    ++live_a;
    if (!a) begin
      exp_a += live_a;
      live_a = 0;
    end
    ++live_b;
    if (!b) begin
      exp_b += live_b;
      live_b = 0;
    end
    if (c) ++live_ia;
    if (!a && live_ia != 0) begin
      ++ticks_ia;
      live_ia = 0;
    end
    if (!a && live_na != 0) begin
      ++ticks_na;
      live_na = 0;
    end
    if (c) ++live_na;
    if (c) ++live_ib;
    if (!b && live_ib != 0) begin
      ++ticks_ib;
      live_ib = 0;
    end
    if (c) begin
      live_dis = 0;
    end else begin
      ++live_dis;
      if (!a) begin
        exp_dis += live_dis;
        live_dis = 0;
      end
    end
    cyc <= cyc + 1;
    crc <= {crc[30:0], crc[31] ^ crc[21] ^ crc[1] ^ crc[0]};
    a <= crc[0];
    b <= crc[2];
    c <= crc[5];
    if (cyc == 40) $finish;
  end

  property p_alw;
    always a;
  endproperty
  property p_arg(x);
    always x;
  endproperty
  property p_impl;
    always (a |-> ##1 b);
  endproperty
  property p_disable;
    disable iff (c) always [0:$] a;
  endproperty
  property p_clk;
    @(posedge clk) always b;
  endproperty
  property p_wrap;
    p_alw;
  endproperty
  // Not 'always p', so not reduced
  property p_range;
    always [1:$] a;
  endproperty

  property p_wrap2;
    p_wrap;
  endproperty

  int fails_alw = 0, fails_arg = 0, fails_impl = 0, fails_disable = 0, fails_clk = 0;
  int fails_wrap = 0, fails_wrap2 = 0, fails_range = 0, fails_param = 0;
  assert property (@(posedge clk) p_alw)
  else fails_alw++;
  assert property (@(posedge clk) p_arg(b))
  else fails_arg++;
  assert property (@(posedge clk) p_impl)
  else fails_impl++;
  assert property (@(posedge clk) p_disable)
  else fails_disable++;
  assert property (p_clk)
  else fails_clk++;
  assert property (@(posedge clk) p_wrap)
  else fails_wrap++;
  assert property (@(posedge clk) p_wrap2)
  else fails_wrap2++;
  assert property (@(posedge clk) p_range)
  else fails_range++;
  // Under another property operator the body keeps its 'always', and the instance fails as the
  // property written out does: once on each tick its attempts fail, not once per attempt, which
  // is a limit of the written-out property
  int fails_nest_impl = 0, fails_nest_next = 0, fails_nest_if = 0, fails_nest_arg = 0;
  int fails_nest_wrap = 0;
  assert property (@(posedge clk) c |-> p_alw)
  else fails_nest_impl++;
  assert property (@(posedge clk) c |=> p_alw)
  else fails_nest_next++;
  assert property (@(posedge clk) if (c) p_alw)
  else fails_nest_if++;
  assert property (@(posedge clk) c |-> p_arg(b))
  else fails_nest_arg++;
  assert property (@(posedge clk) c |-> p_wrap)
  else fails_nest_wrap++;
  // A bound that is a parameter is only constant after widthing
  localparam int ZERO = 0;
  assert property (@(posedge clk) always [ZERO:$] a)
  else fails_param++;

  int ref_fails_alw = 0, ref_fails_arg = 0, ref_fails_impl = 0, ref_fails_disable = 0;
  int ref_fails_range = 0;
  assert property (@(posedge clk) a)
  else ref_fails_alw++;
  assert property (@(posedge clk) b)
  else ref_fails_arg++;
  assert property (@(posedge clk) a |-> ##1 b)
  else ref_fails_impl++;
  assert property (@(posedge clk) disable iff (c) a)
  else ref_fails_disable++;
  assert property (@(posedge clk) always [1:$] a)
  else ref_fails_range++;
  int ref_fails_nest_impl = 0, ref_fails_nest_next = 0, ref_fails_nest_if = 0;
  int ref_fails_nest_arg = 0;
  assert property (@(posedge clk) c |-> always a)
  else ref_fails_nest_impl++;
  assert property (@(posedge clk) c |=> always a)
  else ref_fails_nest_next++;
  assert property (@(posedge clk) if (c) always a)
  else ref_fails_nest_if++;
  assert property (@(posedge clk) c |-> always b)
  else ref_fails_nest_arg++;

  // Counts read in final (Postponed) to avoid same-timestep races.
  final begin
    `checkd(fails_alw, exp_a);
    `checkd(fails_arg, exp_b);
    `checkd(fails_impl, ref_fails_impl);
    `checkd(fails_disable, exp_dis);
    `checkd(fails_clk, exp_b);
    `checkd(fails_wrap, exp_a);
    `checkd(fails_wrap2, exp_a);
    `checkd(fails_range, ref_fails_range);
    `checkd(fails_param, exp_a);
    `checkd(fails_nest_impl, ref_fails_nest_impl);
    `checkd(fails_nest_next, ref_fails_nest_next);
    `checkd(fails_nest_if, ref_fails_nest_if);
    `checkd(fails_nest_arg, ref_fails_nest_arg);
    `checkd(fails_nest_wrap, ref_fails_nest_impl);
    `checkd(ref_fails_nest_impl, ticks_ia);
    `checkd(ref_fails_nest_next, ticks_na);
    `checkd(ref_fails_nest_if, ticks_ia);
    `checkd(ref_fails_nest_arg, ticks_ib);
    `checkd(ref_fails_range, 16);
    `checkd(ref_fails_alw, 17);
    `checkd(ref_fails_arg, 19);
    `checkd(ref_fails_impl, 12);
    `checkd(ref_fails_disable, 6);
    $write("*-* All Finished *-*\n");
  end
endmodule
