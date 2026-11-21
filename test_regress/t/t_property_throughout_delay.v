// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// A throughout starting after a multi-cycle delay (IEEE 1800-2023 16.9.9),
// checked against a reference model. Attempts start at most every 8 cycles, so
// they never overlap.

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module t (
    input clk
);

  localparam int CYCLES = 1000;
  int cyc = 0;
  bit [63:0] crc = 64'h5aef0c8d_d70a4497;
  wire d = cyc < CYCLES && cyc[2:0] == 0 && crc[0];
  wire f = crc[4] | crc[5];
  wire g = crc[8];
  // Dense attempts, so that the delay ring holds several at once
  wire dd = cyc < CYCLES && crc[12];

  bit dh[CYCLES + 8], ddh[CYCLES + 8], fh[CYCLES + 8], gh[CYCLES + 8];
  always @(posedge clk) begin
    dh[cyc] = d;
    ddh[cyc] = dd;
    fh[cyc] = f;
    gh[cyc] = g;
    cyc <= cyc + 1;
    crc <= {crc[62:0], crc[63] ^ crc[2] ^ crc[0]};
  end

  // True if f holds from cycle s for n cycles
  function automatic bit fHolds(int s, int n);
    for (int k = 0; k < n; k++) if (!fh[s+k]) return 0;
    return 1;
  endfunction

  int fail_range = 0;
  assert property (@(posedge clk) d |-> ##2 (f throughout ##[0:2] (f && g)))
  else fail_range++;
  function automatic int refRange();
    int n = 0;
    for (int s = 0; s < CYCLES; s++) begin
      automatic bit ok = 0;
      for (int k = 0; k <= 2; k++) if (fHolds(s + 2, k + 1) && gh[s+2+k]) ok = 1;
      if (dh[s] && !ok) n++;
    end
    return n;
  endfunction

  int fail_fixed = 0;
  assert property (@(posedge clk) d |-> ##3 (f throughout (1'b1 ##2 g)))
  else fail_fixed++;
  function automatic int refFixed();
    int n = 0;
    for (int s = 0; s < CYCLES; s++) n += int'(dh[s] && !(fHolds(s + 3, 3) && gh[s+5]));
    return n;
  endfunction

  int fail_nested = 0;
  assert property (@(posedge clk)
      d |-> ##2 (f throughout (1'b1 ##2 (g throughout (1'b1 ##1 1'b1)))))
  else fail_nested++;
  function automatic int refNested();
    int n = 0;
    for (int s = 0; s < CYCLES; s++) n += int'(dh[s] && !(fHolds(s + 2, 4) && gh[s+4] && gh[s+5]));
    return n;
  endfunction

  // Each failing attempt runs the fail action (IEEE 1800-2023 16.14.1)
  int fail_range_dense = 0;
  assert property (@(posedge clk) dd |-> ##2 (f throughout ##[0:2] (f && g)))
  else fail_range_dense++;
  function automatic int refRangeDense();
    int n = 0;
    for (int s = 0; s < CYCLES; s++) begin
      automatic int failAt = s + 4;
      for (int k = 0; k <= 2; k++) begin
        if (!fh[s+2+k]) begin
          failAt = s + 2 + k;
          break;
        end
        if (gh[s+2+k]) begin
          failAt = -1;
          break;
        end
      end
      n += int'(ddh[s] && failAt >= 0);
    end
    return n;
  endfunction

  int fail_fixed_dense = 0;
  assert property (@(posedge clk) dd |-> ##3 (f throughout (1'b1 ##2 g)))
  else fail_fixed_dense++;
  function automatic int refFixedDense();
    int n = 0;
    for (int s = 0; s < CYCLES; s++) begin
      automatic int failAt = gh[s+5] ? -1 : s + 5;
      for (int k = 2; k >= 0; k--) if (!fh[s+3+k]) failAt = s + 3 + k;
      n += int'(ddh[s] && failAt >= 0);
    end
    return n;
  endfunction

  always @(negedge clk) begin
    if (cyc == CYCLES + 8) begin
      `checkd(fail_range, refRange());
      `checkd(fail_fixed, refFixed());
      `checkd(fail_nested, refNested());
      `checkd(fail_range_dense, refRangeDense());
      `checkd(fail_fixed_dense, refFixedDense());
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end

endmodule
