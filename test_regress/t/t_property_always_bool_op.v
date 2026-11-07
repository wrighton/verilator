// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// An unbounded always as the property operand of a property 'and' or 'or' with a boolean
// (IEEE 1800-2023 16.12.5, 16.12.4, 16.12.11), checked tick by tick against a reference
// model of which attempts fail.
module t;
  logic clk = 0;
  always #5 clk = ~clk;

  localparam int CYCLES = 200;
  int cyc = 0;
  bit [63:0] crc = 64'h5aef0c8d_d70a4497;
  wire a = crc[0] | crc[1] | crc[2];
  wire b = crc[4] | crc[5];

  bit fail_and, fail_or, fail_true;
  int ticks_and = 0, ticks_or = 0;
  assert property (@(posedge clk) (always a) and b)
  else fail_and = 1;
  assert property (@(posedge clk) (always a) or b)
  else fail_or = 1;
  assert property (@(posedge clk) 1'b1 or (always [0:$] a))
  else fail_true = 1;

  // Attempts still obligated to 'always a'
  bit alive_and[CYCLES], alive_or[CYCLES];
  bit ref_and, ref_or;
  always @(posedge clk) begin
    ref_and = !b;
    ref_or = 0;
    alive_and[cyc] = b;
    alive_or[cyc] = !b;
    for (int s = 0; s <= cyc; s++) begin
      if (!a && alive_and[s]) begin
        ref_and = 1;
        alive_and[s] = 0;
      end
      if (!a && alive_or[s]) begin
        ref_or = 1;
        alive_or[s] = 0;
      end
    end
    cyc <= cyc + 1;
    crc <= {crc[62:0], crc[63] ^ crc[2] ^ crc[0]};
  end

  always @(negedge clk) begin
    `checkd(fail_and, ref_and);
    `checkd(fail_or, ref_or);
    `checkd(fail_true, 0);
    ticks_and += int'(fail_and);
    ticks_or += int'(fail_or);
    fail_and = 0;
    fail_or = 0;
    if (cyc == CYCLES - 1) begin
      // Not vacuous
      `checkd(ticks_and > 10, 1);
      `checkd(ticks_or > 5, 1);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
