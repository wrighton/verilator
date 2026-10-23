// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Each rejected thread of a negated property's operand is a pass of the property, not a
// failure (IEEE 1800-2023 16.12.3)

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module t (
    input clk
);

  int cyc;
  reg [63:0] crc;

  // Non-adjacent CRC bits to avoid LFSR shift correlation
  wire a = crc[0];
  wire b = crc[4];
  wire c = crc[8];
  wire g = crc[12] | crc[13];

  // Counted with blocking increments, as several attempts can end on one tick
  int fail1 = 0, ref_fail1 = 0;
  int pass1 = 0, op_fail1 = 0;

  assert property (@(posedge clk) disable iff (cyc < 2) not (a ##1 b ##1 c)) ++pass1;
  else ++fail1;
  // Its passes are the failures of the operand
  assert property (@(posedge clk) disable iff (cyc < 2) a ##1 b ##1 c)
  else ++op_fail1;

  // A throughout guard drop rejects every live thread; the fail action lets the pass action run
  // on ticks where another attempt matches
  int pass2 = 0, op_fail2 = 0;
  assert property (@(posedge clk) disable iff (cyc < 2) not (g throughout (a ##1 b ##1 c))) ++pass2;
  else $write("");
  assert property (@(posedge clk) disable iff (cyc < 2) g throughout (a ##1 b ##1 c))
  else ++op_fail2;

  always @(posedge clk) begin
    if (cyc >= 4 && $past(a, 2) && $past(b) && c) ++ref_fail1;
  end

  // Stimulus on negedge so properties sample stable values
  always @(negedge clk) begin
    cyc <= cyc + 1;
    crc <= {crc[62:0], crc[63] ^ crc[2] ^ crc[0]};
    if (cyc == 0) begin
      crc <= 64'h5aef0c8d_d70a4497;
    end
    else if (cyc == 99) begin
      `checkd(fail1, ref_fail1);
      `checkd(pass1, op_fail1);
      `checkd(ref_fail1, 10);
      `checkd(op_fail1, 87);
      `checkd(pass2, op_fail2);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
