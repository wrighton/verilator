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

// $past, $sampled, $stable and $changed of whole unpacked structures (IEEE 1800-2023 16.9.3)
module t (
    input clk
);

  typedef struct {
    int a;
    bit [3:0] b[2];
  } st_t;
  typedef struct packed {
    bit [2:0] a;
    bit [3:0] b;
  } pst_t;
  typedef struct {
    pst_t p;
    bit [6:0] c;
  } nst_t;

  int cyc = 0;
  // Not initialized in the declaration, so default sampled values are 0
  st_t st;
  nst_t nst;
  st_t sts[2];

  initial begin
    st = '{5, '{4'd1, 4'd2}};
    nst = '{'{3'd1, 4'd2}, 7'd3};
    sts = '{'{1, '{4'd3, 4'd4}}, '{2, '{4'd5, 4'd6}}};
  end

  always @(posedge clk) begin
    cyc <= cyc + 1;
    // Each changes on some cycles only
    if (cyc % 5 == 3) st.b[1] <= st.b[1] + 4'd1;
    if (cyc % 3 == 1) nst.c <= nst.c + 7'd1;
    if (cyc % 4 == 2) sts[1].a <= sts[1].a + 1;
  end

  // Sampled values at the previous two ticks, starting from the default sampled values
  st_t tick_st = '{0, '{0, 0}};
  st_t tick2_st = '{0, '{0, 0}};
  nst_t tick_nst = '{'{0, 0}, 0};
  st_t tick_sts[2] = '{'{0, '{0, 0}}, '{0, '{0, 0}}};
  always @(posedge clk) begin
    `checkp($past(st), tick_st);
    `checkp($past(st, 2), tick2_st);
    `checkp($sampled(st), st);
    `checkd($stable(st), st == tick_st);
    `checkd($changed(st), st != tick_st);
    `checkp($past(nst), tick_nst);
    `checkd($stable(nst), nst == tick_nst);
    `checkp($past(sts), tick_sts);
    `checkd($changed(sts), sts != tick_sts);
    // Selects of the default sampled value of a structure
    `checkd($past(st.a), tick_st.a);
    `checkd($past(st.b[1]), tick_st.b[1]);
    `checkd($past(nst.p.b), tick_nst.p.b);
    `checkd($past(sts[1].a), tick_sts[1].a);
    tick_st <= st;
    tick2_st <= tick_st;
    tick_nst <= nst;
    tick_sts <= sts;
  end

  // st changes after cycles 3, 8, 13, so is unstable on cycles 0, 4, 9, 14
  int stable_fails = 0;
  assert property (@(posedge clk) cyc > 15 || $stable(st))
  else stable_fails++;

  always @(posedge clk) begin
    if (cyc == 20) begin
      `checkd(stable_fails, 4);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end

endmodule
