// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__, `__LINE__, (gotv), (expv)); `stop; end while(0);
`define checkp(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%p exp=%p\n", `__FILE__, `__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// $past, $sampled, $stable and $changed of whole unpacked arrays and structures
// (IEEE 1800-2023 16.9.3)
module t (
    input clk
);

  typedef struct {
    int a;
    bit [3:0] b[2];
  } st_t;

  int cyc = 0;
  // Not initialized in the declaration, so default sampled values are 0
  bit [6:0] regs[3:1];
  int m[2][1:3];
  st_t st;
  struct packed {
    bit [2:0] a;
    bit [3:0] b;
  } pst;
  // Initialized, so default sampled values are the initial values
  bit [3:0] init_arr[2] = '{4'd3, 4'd4};
  // 4-state, so default sampled values are unknown
  logic [6:0] regs4[4];

  initial begin
    regs = '{7'd1, 7'd2, 7'd3};
    m = '{'{1, 2, 3}, '{4, 5, 6}};
    st = '{5, '{4'd1, 4'd2}};
    pst = '{3'd1, 4'd2};
    regs4 = '{default: 7'd9};
  end

  always @(posedge clk) begin
    cyc <= cyc + 1;
    // Each changes on some cycles only
    if (cyc % 3 == 1) regs[cyc%3+1] <= regs[cyc%3+1] + 7'd1;
    if (cyc % 4 == 2) m[1][2] <= m[1][2] + 1;
    if (cyc % 5 == 3) st.b[1] <= st.b[1] + 4'd1;
    if (cyc == 6) init_arr[0] <= 4'd7;
    pst.b <= pst.b + 4'd1;
    if (cyc % 3 == 0) regs4[1] <= regs4[1] + 7'd1;
    if (cyc == 20) begin
      `checkd(stable_fails, 6);
      `checkd(changed_fails, 6);
      `checkd(formal_fails, 6);
      `checkd(regs4_fails, 0);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end

  // Sampled values at the previous two ticks, starting from the default sampled values
  bit [6:0] tick_regs[3:1] = '{default: 0};
  bit [6:0] tick2_regs[3:1] = '{default: 0};
  int tick_m[2][1:3] = '{default: 0};
  st_t tick_st = '{0, '{0, 0}};
  bit [3:0] tick_init_arr[2] = '{4'd3, 4'd4};
  bit [6:0] tick_pst = 0;
  always @(posedge clk) begin
    `checkp($past(regs), tick_regs);
    `checkp($past(regs, 2), tick2_regs);
    `checkp($sampled(regs), regs);
    `checkd($stable(regs), regs == tick_regs);
    `checkd($changed(regs), regs != tick_regs);
    `checkp($past(m), tick_m);
    `checkd($stable(m), m == tick_m);
    `checkp($past(st), tick_st);
    `checkd($changed(st), st != tick_st);
    `checkp($past(init_arr), tick_init_arr);
    `checkd($stable(init_arr), init_arr == tick_init_arr);
    `checkd($past(pst), tick_pst);
    // Selects of the default sampled value of an aggregate
    `checkd($past(regs[2]), tick_regs[2]);
    `checkd($past(m[1][2]), tick_m[1][2]);
    `checkd($past(st.a), tick_st.a);
    `checkd($past(st.b[1]), tick_st.b[1]);
    `checkp($past_gclk(regs), tick_regs);
    `checkd($stable_gclk(m), m == tick_m);
    `checkd($changed_gclk(st), st != tick_st);
    tick_regs <= regs;
    tick2_regs <= tick_regs;
    tick_m <= m;
    tick_st <= st;
    tick_init_arr <= init_arr;
    tick_pst <= pst;
  end

  // regs changes after cycles 1, 4, 7, ..., so is unstable on cycles 0, 2, 5, 8, 11, 14
  int stable_fails = 0;
  assert property (@(posedge clk) cyc > 15 || $stable(regs))
  else stable_fails++;

  int changed_fails = 0;
  assert property (@(posedge clk) cyc > 15 || !$changed(regs))
  else changed_fails++;

  property p_stable(x);
    @(posedge clk) cyc > 15 || $stable(x);
  endproperty
  int formal_fails = 0;
  assert property (p_stable(regs))
  else formal_fails++;

  global clocking @(posedge clk);
  endclocking

  // The unknown default sampled values only affect the first tick
  int regs4_fails = 0;
  assert property (@(posedge clk) cyc == 0 || $stable(regs4) == (cyc % 3 != 1))
  else regs4_fails++;

endmodule
