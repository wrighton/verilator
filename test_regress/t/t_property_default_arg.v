// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

// Default actual arguments of sequence and property formal arguments
// (IEEE 1800-2023 16.8, 16.12). Each instance is compared with the same
// assertion written out.
module t (
  input clk
);
  int unsigned crc = 32'h1;
  logic a, b, c;
  int cyc = 0;

  always @(posedge clk) begin
    cyc <= cyc + 1;
    crc <= {crc[30:0], crc[31] ^ crc[21] ^ crc[1] ^ crc[0]};
    a <= crc[0];
    b <= crc[2];
    c <= crc[5];
    if (cyc == 40) $finish;
  end

  // Typed formal with a constant default, omitted and overridden
  property prop_dsbl(logic dsbl = 1'b0, logic pv, logic x, logic y);
    !dsbl && pv |-> ##1 (x == y);
  endproperty
  int fails_omit = 0, ref_fails_omit = 0;
  assert property (@(posedge clk) prop_dsbl(, a, b, c))
  else fails_omit++;
  assert property (@(posedge clk) a |-> ##1 (b == c))
  else ref_fails_omit++;
  int fails_override = 0, ref_fails_override = 0;
  assert property (@(posedge clk) prop_dsbl(c, a, b, c))
  else fails_override++;
  assert property (@(posedge clk) !c && a |-> ##1 (b == c))
  else ref_fails_override++;

  // Untyped formal defaulting to a signal of the declaration scope
  sequence seq_def(x, y = b);
    x ##1 y;
  endsequence
  int fails_sig = 0, ref_fails_sig = 0;
  assert property (@(posedge clk) seq_def(a))
  else fails_sig++;
  assert property (@(posedge clk) a ##1 b)
  else ref_fails_sig++;

  // Untyped formal defaulting to a constant used as a cycle delay
  property prop_delay(x, n = 2);
    x |-> ##n x;
  endproperty
  int fails_delay = 0, ref_fails_delay = 0;
  assert property (@(posedge clk) prop_delay(a))
  else fails_delay++;
  assert property (@(posedge clk) a |-> ##2 a)
  else ref_fails_delay++;

  // Instance without an argument list
  property prop_nine(int nine = 9);
    cyc == 9 |-> cyc == nine;
  endproperty
  int fails_nine = 0;
  assert property (@(posedge clk) prop_nine)
  else fails_nine++;

  // Counts read in final (Postponed) to avoid same-timestep races.
  final begin
    `checkd(fails_omit, ref_fails_omit);
    `checkd(fails_override, ref_fails_override);
    `checkd(fails_sig, ref_fails_sig);
    `checkd(fails_delay, ref_fails_delay);
    `checkd(ref_fails_omit, 7);
    `checkd(ref_fails_override, 5);
    `checkd(ref_fails_sig, 26);
    `checkd(ref_fails_delay, 11);
    `checkd(fails_nine, 0);
    $write("*-* All Finished *-*\n");
  end
endmodule
