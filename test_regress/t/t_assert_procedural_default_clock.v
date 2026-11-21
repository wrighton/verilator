// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

// IEEE 1800-2023 16.9.3, 16.14.6, 16.16: in an always procedure with an inferred
// clock, procedural concurrent assertions and sampled value functions use that
// clock, not default clocking; each is compared with the same check explicitly
// clocked.
module t (
  input clk
);
  int unsigned crc = 32'h1;
  bit a, b, c;
  bit clk2 = 0;
  bit x;
  int cyc = 0;

  always @(posedge clk) begin
    cyc <= cyc + 1;
    crc <= {crc[30:0], crc[31] ^ crc[21] ^ crc[1] ^ crc[0]};
    a <= crc[0];
    b <= crc[2];
    c <= crc[5];
    clk2 <= ~clk2;
    if (cyc == 40) $finish;
  end

  default clocking @(posedge clk2);
  endclocking

  int fails1 = 0, fails2 = 0, fails3 = 0, rises = 0;
  always @(posedge clk) begin
    assert property (a |-> b)
    else fails1++;
    assert property (a |-> ##1 b)
    else fails2++;
    assert property ($rose(a) |-> c)
    else fails3++;
    if ($rose(a)) rises++;
  end

  // Lowering the first assertion gives its $rose the clock, which must not stop the
  // inference for the rest of the procedure
  int fails4 = 0, fails5 = 0, rises2 = 0;
  always @(posedge clk) begin
    assert property (a |-> ##1 $rose(b))
    else fails4++;
    assert property (b |-> ##1 c)
    else fails5++;
    if ($rose(c)) rises2++;
  end

  // No clock is inferred, as the edge variable is used in the body
  int def_rises = 0;
  always @(posedge clk) begin
    x <= clk;
    if ($rose(a)) def_rises++;
  end

  // An empty procedure
  always @(posedge clk);

  // Not in a procedure
  int def_fails = 0;
  assert property (a |-> ##1 c)
  else def_fails++;

  int ref_fails1 = 0, ref_fails2 = 0, ref_fails3 = 0, ref_rises = 0;
  int ref_def_fails = 0, ref_fails4 = 0, ref_fails5 = 0, ref_rises2 = 0;
  bit c_q = 0;
  bit a_q = 0;
  assert property (@(posedge clk) a |-> b)
  else ref_fails1++;
  assert property (@(posedge clk) a |-> ##1 b)
  else ref_fails2++;
  assert property (@(posedge clk) $rose(a) |-> c)
  else ref_fails3++;
  always @(posedge clk) begin
    if (a && !a_q) ref_rises++;
    a_q <= a;
    if (c && !c_q) ref_rises2++;
    c_q <= c;
  end
  assert property (@(posedge clk) a |-> ##1 $rose(b))
  else ref_fails4++;
  assert property (@(posedge clk) b |-> ##1 c)
  else ref_fails5++;
  assert property (@(posedge clk2) a |-> ##1 c)
  else ref_def_fails++;

  // Counts read in final (Postponed) to avoid same-timestep races.
  final begin
    `checkd(fails1, ref_fails1);
    `checkd(fails2, ref_fails2);
    `checkd(fails3, ref_fails3);
    `checkd(rises, ref_rises);
    `checkd(fails4, ref_fails4);
    `checkd(fails5, ref_fails5);
    `checkd(rises2, ref_rises2);
    `checkd(def_rises == ref_rises, 1'b0);
    `checkd(def_fails, ref_def_fails);
    `checkd(ref_fails1, 13);
    `checkd(ref_fails2, 12);
    `checkd(ref_fails3, 5);
    `checkd(ref_rises, 12);
    `checkd(def_rises, 11);
    `checkd(ref_def_fails, 5);
    `checkd(ref_fails4, 14);
    `checkd(ref_fails5, 11);
    `checkd(ref_rises2, 11);
    $write("*-* All Finished *-*\n");
  end
endmodule
