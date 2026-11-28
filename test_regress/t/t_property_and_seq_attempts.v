// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv, expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// An 'and' of two sequences fails each attempt once, on its first failing operand, also where
// one operand is longer (IEEE 1800-2023 16.9.5, 16.14.1); an 'and' of booleans after a range
// in a consequent keeps the lowering of before, and an 'or' operand passing decides its attempt.
module t;
  localparam int NCYC = 200;

  bit clk = 0;
  always #5 clk = ~clk;
  int cyc = 0;
  bit [30:0] lfsr = 31'h5a5a_1234;
  wire a = lfsr[2] | lfsr[11];
  wire c = lfsr[5] | lfsr[19];
  wire e = lfsr[23] | lfsr[7];
  // A directed attempt on tick 2
  wire dd = cyc == 2, de = cyc == 2, dc = cyc == 3, db = 1'b0;

  int fails[5];
  // verilog_format: off
  assert property (@(posedge clk) (a ##2 e) and c) else ++fails[0];
  assert property (@(posedge clk) c and (a ##2 e)) else ++fails[1];
  assert property (@(posedge clk) dd or (de |=> (dc ##[2:4] (db and de)))) else ++fails[2];
  assert property (@(posedge clk) (de |=> (dc ##[2:4] (db and de))) or dd) else ++fails[3];
  assert property (@(posedge clk) dd or (de |=> (dc ##2 (db and de)))) else ++fails[4];
  // verilog_format: on

  bit ha[NCYC + 4], hc[NCYC + 4], he[NCYC + 4];
  always @(posedge clk) begin
    ha[cyc] = a;
    hc[cyc] = c;
    he[cyc] = e;
    cyc <= cyc + 1;
    lfsr <= {lfsr[29:0], lfsr[30] ^ lfsr[27]};
  end

  always @(negedge clk) begin
    if (cyc == NCYC) begin
      automatic int expFails = 0;
      for (int s = 0; s < NCYC; ++s) begin
        if (!ha[s] || !hc[s]) ++expFails;
        else if (s + 2 < NCYC && !he[s+2]) ++expFails;
      end
      `checkd(fails[0], expFails);
      `checkd(fails[1], expFails);
      `checkd(fails[2], 0);
      `checkd(fails[3], 0);
      `checkd(fails[4], 0);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
