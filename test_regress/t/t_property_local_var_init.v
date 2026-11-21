// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module t (
    input clk
);

  int cyc = 0;
  logic [6:0] v;
  localparam int INIT = 5;

  // Property local variables read their initializer value (IEEE 1800-2023 16.10)
  int fail_overlap = 0;
  int fail_delay = 0;
  int fail_param = 0;
  int fail_signed = 0;
  int fail_nested = 0;
  int fail_assigned = 0;
  int fail_wrong = 0;
  property p_overlap;
    int x = 5;
    @(posedge clk) 1 |-> (x == 5);
  endproperty
  property p_delay;
    logic [6:0] x = 7'h55;
    @(posedge clk) v[0] ##1 v[1] |-> ##2 (x == 7'h55);
  endproperty
  property p_param;
    int x = INIT + 1;
    logic [6:0] w = 5;
    @(posedge clk) (x == 6) && (w + 7'd124 == 7'd1);
  endproperty
  property p_signed;
    int x = -3;
    @(posedge clk) v[2] |=> (x < 0);
  endproperty
  property p_check(int y);
    int z = 3;
    y == z;
  endproperty
  // The match item precedes the read, so the initializer, constant or not, is not seen
  property p_assigned;
    logic [6:0] x = v ^ 7'h7f;
    logic [6:0] y = 7'h7f;
    @(posedge clk) (v[3], x = v, y = v) |=> (x == $past(v)) && (y == x);
  endproperty
  // A zero initial value only read after the match item, and initializers never read
  int fail_zero = 0;
  property p_zero;
    logic [6:0] x = 0;
    int unread = cyc;
    int unread_const = 3;
    @(posedge clk) (v[6], x = v + 7'd1) |=> (x == $past(v) + 7'd1);
  endproperty
  assert property (p_zero)
  else fail_zero++;
  // Fails when the initializer is seen, as needed for the test to fail without it
  property p_wrong;
    int x = 5;
    @(posedge clk) v[4] |-> (x != 5);
  endproperty
  assert property (p_overlap)
  else fail_overlap++;
  assert property (p_delay)
  else fail_delay++;
  assert property (p_param)
  else fail_param++;
  assert property (p_signed)
  else fail_signed++;
  assert property (@(posedge clk) v[5] |-> p_check(3))
  else fail_nested++;
  assert property (p_assigned)
  else fail_assigned++;
  assert property (p_wrong)
  else fail_wrong++;

  always @(posedge clk) begin
    cyc <= cyc + 1;
    v <= 7'(cyc * 37 + 11);
    if (cyc == 30) begin
      `checkd(fail_overlap, 0);
      `checkd(fail_delay, 0);
      `checkd(fail_param, 0);
      `checkd(fail_signed, 0);
      `checkd(fail_nested, 0);
      `checkd(fail_assigned, 0);
      `checkd(fail_zero, 0);
      `checkd(fail_wrong, 15);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end

endmodule
