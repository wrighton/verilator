// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__, `__LINE__, (gotv), (expv)); `stop; end while(0);
`define checkr(gotv,expv) do if ((gotv) != (expv)) begin $write("%%Error: %s:%0d: got=%f exp=%f\n", `__FILE__, `__LINE__, (gotv), (expv)); `stop; end while (0);
// verilog_format: on

module t (
    input clk
);

  int cyc = 0;
  // Initialized, so its default sampled value is 1.25 (IEEE 1800-2023 16.5.1)
  real r = 1.25;
  // Not initialized, so its default sampled value is 0.0
  real s;

  always @(posedge clk) begin
    cyc <= cyc + 1;
    r <= r + 0.25;
    if (cyc == 3) s <= 0.25;
    // Sampled value functions keep the real value (IEEE 1800-2023 16.9.3)
    `checkr($past(r), cyc == 0 ? 1.25 : r - 0.25);
    `checkr($sampled(r), r);
    `checkd($stable(r), cyc == 0);
    `checkd($changed(s), cyc == 4);
    if (cyc == 10) begin
      `checkd(past_pass, 10);
      `checkd(past_fail, 0);
      `checkd(changed_fail, 1);
      `checkd(stable_fail, 1);
      `checkd(formal_fail, 0);
      `checkd(local_fail, 0);
      `checkd(local_wrong_fail, 8);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end

  int past_pass = 0;
  int past_fail = 0;
  assert property (@(posedge clk) $past(r) > 1.0 && $sampled(r) >= $past(r)) past_pass++;
  else past_fail++;

  int changed_fail = 0;
  assert property (@(posedge clk) $changed(r))
  else changed_fail++;

  int stable_fail = 0;
  assert property (@(posedge clk) $stable(s))
  else stable_fail++;

  property p_past_above(real x);
    @(posedge clk) $past(x) > 1.0;
  endproperty
  int formal_fail = 0;
  assert property (p_past_above(r))
  else formal_fail++;

  // A real local variable read cycles after its assignment
  property p_real_local;
    real t;
    @(posedge clk) (1, t = r) |=> ##1 (t == r - 0.5);
  endproperty
  int local_fail = 0;
  assert property (p_real_local)
  else local_fail++;

  property p_real_local_wrong;
    real t;
    @(posedge clk) (1, t = r) |=> ##1 (t == r - 0.25);
  endproperty
  int local_wrong_fail = 0;
  assert property (p_real_local_wrong)
  else local_wrong_fail++;

endmodule
