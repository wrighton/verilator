// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Property 'and' of implications: an attempt failing both operands on one
// tick runs the fail action once (IEEE 1800-2023 16.12.5, 16.14.1), checked
// against a reference model.

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module t (
    input clk
);

  int cyc = 0;
  bit [63:0] crc = 64'h5aef0c8d_d70a4497;
  wire a = crc[0];
  wire b = crc[5];
  wire x = crc[11];
  wire y = crc[17];

  always @(posedge clk) begin
    cyc <= cyc + 1;
    crc <= {crc[62:0], crc[63] ^ crc[2] ^ crc[0]};
  end

  // Sampled history: [0] this cycle, [k] k cycles earlier
  bit [2:0] ah, bh, xh, yh;
  always_comb begin
    ah[0] = a;
    bh[0] = b;
    xh[0] = x;
    yh[0] = y;
  end
  always @(posedge clk) begin
    ah[2:1] <= ah[1:0];
    bh[2:1] <= bh[1:0];
    xh[2:1] <= xh[1:0];
    yh[2:1] <= yh[1:0];
  end

  // Both operands end one cycle after the attempt
  int fail_next = 0, ref_next = 0;
  assert property (@(posedge clk) (1'b1 #=# a) and (1'b1 |=> b))
  else fail_next++;
  always @(posedge clk) if (cyc > 0) ref_next += int'(!ah[0] || !bh[0]);

  int fail_impl = 0, ref_impl = 0;
  assert property (@(posedge clk) (x |-> ##1 a) and (y |-> ##1 b))
  else fail_impl++;
  always @(posedge clk) if (cyc > 0) ref_impl += int'((xh[1] && !ah[0]) || (yh[1] && !bh[0]));

  // Followed-by failing on its antecedent and both consequents on the attempt cycle
  int fail_now = 0, ref_now = 0;
  assert property (@(posedge clk) (x #-# a) and (y |-> b))
  else fail_now++;
  always @(posedge clk) ref_now += int'(!(x && a) || (y && !b));

  // Operands of different lengths: failures on one tick are of different attempts
  int fail_diff = 0, ref_diff = 0;
  assert property (@(posedge clk) (x && y |=> a) and (x && !y |=> ##1 b))
  else fail_diff++;
  always @(posedge clk)
    if (cyc > 1) ref_diff += int'(xh[1] && yh[1] && !ah[0]) + int'(xh[2] && !yh[2] && !bh[0]);

  always @(negedge clk) begin
    if (cyc == 200) begin
      `checkd(fail_next, ref_next);
      `checkd(fail_impl, ref_impl);
      `checkd(fail_now, ref_now);
      `checkd(fail_diff, ref_diff);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end

endmodule
