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

// A sequence instance as the actual argument of an untyped property formal
// (IEEE 1800-2023 16.8.2, 16.12)
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

  sequence s_ab;
    a ##1 b;
  endsequence
  sequence s_arg(x, y);
    x ##2 y;
  endsequence

  property p_ovl(q);
    q |-> c;
  endproperty
  property p_nonovl(q);
    q |=> c;
  endproperty

  int count_fail1 = 0;
  int count_fail2 = 0;
  int count_fail3 = 0;
  int count_fail4 = 0;
  int count_fail5 = 0;
  int count_fail6 = 0;
  int count_fail7 = 0;
  int count_fail8 = 0;

  // Test 1/2: multi-cycle sequence instance, overlapped implication, vs inline
  assert property (disable iff (cyc < 2) p_ovl(s_ab))
  else count_fail1 <= count_fail1 + 1;
  assert property (disable iff (cyc < 2) a ##1 b |-> c)
  else count_fail2 <= count_fail2 + 1;

  // Test 3/4: non-overlapped implication
  assert property (disable iff (cyc < 2) p_nonovl(s_ab))
  else count_fail3 <= count_fail3 + 1;
  assert property (disable iff (cyc < 2) a ##1 b |=> c)
  else count_fail4 <= count_fail4 + 1;

  // Test 5/6: sequence instance with arguments
  assert property (disable iff (cyc < 2) p_ovl(s_arg(b, a)))
  else count_fail5 <= count_fail5 + 1;
  assert property (disable iff (cyc < 2) b ##2 a |-> c)
  else count_fail6 <= count_fail6 + 1;

  // Test 7/8: a multi-bit actual is still reduced to a boolean
  assert property (disable iff (cyc < 2) p_ovl(v))
  else count_fail7 <= count_fail7 + 1;
  assert property (disable iff (cyc < 2) (v != 0) |-> c)
  else count_fail8 <= count_fail8 + 1;

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
      `checkd(count_fail1, count_fail2);
      `checkd(count_fail3, count_fail4);
      `checkd(count_fail5, count_fail6);
      `checkd(count_fail7, count_fail8);
      `checkd(count_fail1, 10);
      `checkd(count_fail3, 16);
      `checkd(count_fail5, 13);
      `checkd(count_fail7, 46);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
