// DESCRIPTION: Verilator: const' casts in sequence match items and action blocks of assertions
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// The sampled value of const'(e) is the current value of e, that of a plain reference its Preponed
// value (IEEE 1800-2023 16.5.1). The match-item data d changes only at negedges, so at a posedge
// both are equal and each property with a cast must behave like its twin without one. The
// antecedents always match, so no attempt succeeds vacuously (16.12.7, 20.11). This test does not
// discriminate the current versus Preponed semantics of const'; they coincide by construction.
module t (
    input clk
);

  int cyc = 0;  // Changes at posedges
  int d = 0;  // Changes at negedges
  int np_plain = 0, np_const = 0, np_plain_same = 0, np_const_same = 0, nf = 0, nact = 0, nref = 0;
  always @(posedge clk) cyc <= cyc + 1;
  always @(negedge clk) d <= d + 1;
  always @(posedge clk) if (d[0]) nref++;  // Reference for the action below

  property p_plain;
    int snap;
    @(posedge clk) (1'b1,
    snap = d
    ) |=> (snap == d - 1);
  endproperty
  property p_const;
    int snap;
    @(posedge clk) (1'b1,
    snap = const'(d)
    ) |=> (snap == d - 1);
  endproperty
  property p_plain_same;
    int snap;
    @(posedge clk) (1'b1,
    snap = d
    ) |-> (snap == d);
  endproperty
  property p_const_same;
    int snap;
    @(posedge clk) (1'b1,
    snap = const'(d)
    ) |-> (snap == d);
  endproperty

  assert property (p_plain) np_plain++;
  else nf++;
  assert property (p_const) np_const++;
  else nf++;
  assert property (p_plain_same) np_plain_same++;
  else nf++;
  assert property (p_const_same) np_const_same++;
  else nf++;

  // d is the same in every region of a posedge, so the action counts as the reference does
  assert property (@(posedge clk) 1'b1 until 1'b1) begin
    if (const'(d[0]) || d < 0) nact++;
  end

  always @(negedge clk) begin
    if (cyc == 21) begin
      // The posedge with sampled cyc k follows k negedges, so its sampled and current d are k
      // |=> attempts of k = 0..19 matured by the posedge with sampled cyc 20; compared with the
      // cast-free twin only, as the count at the first tick is not this test's subject
      if (np_plain < 20) `stop;  // The twin did run: 20 canonically
      `checkd(np_const, np_plain);
      // |-> attempts of k = 0..20, each at its own tick
      `checkd(np_plain_same, 21);
      `checkd(np_const_same, 21);
      `checkd(nf, 0);
      // Posedges k = 0..20 with odd d = k: 10
      `checkd(nref, 10);
      `checkd(nact, nref);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
