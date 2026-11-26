// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv, expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// IEEE 1800-2023 16.9.5: the operands of a sequence 'and' start together, and
// the composite matches at the later operand end. Overlapping attempts each
// pair their own operand matches.

module t (
    input clk
);
  localparam int NCYC = 400;

  integer cyc = 0;
  reg [63:0] crc = 64'h5aef0c8d_d70a4497;

  // Cycles 1-5 hold a and cycles 1-4 hold b, so attempts 1, 2 and 3 of the
  // first 'and' match; then dense random values, then an idle tail
  wire rnd = cyc >= 10 && cyc < NCYC - 8;
  wire a = rnd ? (crc[0] | crc[9]) : (cyc >= 1 && cyc <= 5);
  wire b = rnd ? (crc[17] | crc[26]) : (cyc >= 1 && cyc <= 4);
  wire c = rnd ? crc[33] : (cyc >= 2 && cyc <= 3);
  wire e = rnd ? (crc[41] | crc[50]) : 1'b1;

  bit ha[NCYC];
  bit hb[NCYC];
  bit hc[NCYC];
  bit he[NCYC];
  always @(posedge clk) begin
    ha[cyc] = a;
    hb[cyc] = b;
    hc[cyc] = c;
    he[cyc] = e;
  end

  int count_and = 0;
  int count_and_seq = 0;
  int count_and_swap = 0;
  int count_and_eq = 0;
  int count_intersect = 0;
  int count_range_fail = 0;

  // verilog_format: off
  // Operands of different lengths: each attempt has one match, at its own end tick
  cover property (@(posedge clk) (a [* 3]) and (b [* 2])) ++count_and;
  cover sequence (@(posedge clk) (a [* 3]) and (b [* 2])) ++count_and_seq;
  cover property (@(posedge clk) (b [* 2]) and (a [* 3])) ++count_and_swap;
  // Operands of equal length
  cover property (@(posedge clk) (a [* 2]) and (b ##1 c)) ++count_and_eq;
  cover property (@(posedge clk) (a [* 2]) intersect (b ##1 c)) ++count_intersect;
  // A repetition after a ranged delay fails an attempt only when no delay matches
  assert property (@(posedge clk) 1'b1 ##[1:2] (e [* 2]))
  else ++count_range_fail;
  // verilog_format: on

  function automatic int expected_and();
    int n = 0;
    for (int s = 0; s < NCYC - 2; ++s) begin
      if (ha[s] && ha[s+1] && ha[s+2] && hb[s] && hb[s+1]) ++n;
    end
    return n;
  endfunction

  function automatic int expected_and_eq();
    int n = 0;
    for (int s = 0; s < NCYC - 1; ++s) begin
      if (ha[s] && ha[s+1] && hb[s] && hc[s+1]) ++n;
    end
    return n;
  endfunction

  function automatic int expected_range_fail();
    int n = 0;
    for (int s = 0; s < NCYC - 3; ++s) begin
      if (!(he[s+1] && he[s+2]) && !(he[s+2] && he[s+3])) ++n;
    end
    return n;
  endfunction

  always @(posedge clk) begin
    cyc <= cyc + 1;
    crc <= {crc[62:0], crc[63] ^ crc[2] ^ crc[0]};
    if (cyc == 8) begin
      `checkd(count_and, 3);
    end
    else if (cyc == NCYC - 1) begin
      `checkd(count_and, expected_and());
      `checkd(count_and_seq, expected_and());
      `checkd(count_and_swap, expected_and());
      `checkd(count_and_eq, expected_and_eq());
      `checkd(count_intersect, expected_and_eq());
      `checkd(count_range_fail, expected_range_fail());
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
