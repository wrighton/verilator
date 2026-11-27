// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv, expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Overlapping attempts of a negated followed-by: each rejected attempt of the followed-by
// passes the negation, vacuously when the antecedent does not match, and each match fails it
// (IEEE 1800-2023 16.12.3, 16.12.9). Vacuous passes stop after $assertvacuousoff (16.14.8).

module t (
    input clk
);
  localparam int NCYC = 200;
  localparam int OFF = 100;
  localparam int NPROP = 5;

  integer cyc = 0;
  reg [63:0] crc = 64'h1f2e_3d4c_5b6a_7988;

  wire a = crc[0] | crc[7];
  wire b = crc[13] | crc[21];
  wire c = (cyc % 5) < 3;

  bit ha[NCYC + 4];
  bit hb[NCYC + 4];
  bit hc[NCYC + 4];
  always @(posedge clk) begin
    ha[cyc] = a;
    hb[cyc] = b;
    hc[cyc] = c;
  end

  int passes[NPROP];
  int fails[NPROP];

  // verilog_format: off
  assert property (@(posedge clk) not (c #-# (a ##1 b))) ++passes[0];
  else ++fails[0];
  assert property (@(posedge clk) not (c #=# (a ##1 b))) ++passes[1];
  else ++fails[1];
  assert property (@(posedge clk) not (c #-# (a ##[1:2] b))) ++passes[2];
  else ++fails[2];
  assert property (@(posedge clk) not (c #-# b)) ++passes[3];
  else ++fails[3];
  assert property (@(posedge clk) not (c #=# (a |-> b))) ++passes[4];
  else ++fails[4];
  // verilog_format: on

  // Whether the attempt of property i started on tick s passes, vacuously, and its tick
  task automatic expect_attempt(int i, int s, output bit pass, output bit vacuous,
                                output int tick);
    tick = s;
    vacuous = !hc[s];
    pass = 1;
    if (vacuous) return;
    case (i)
      0: begin
        tick = ha[s] ? s + 1 : s;
        pass = !(ha[s] && hb[s+1]);
      end
      1: begin
        tick = ha[s+1] ? s + 2 : s + 1;
        pass = !(ha[s+1] && hb[s+2]);
      end
      2: begin
        // The negation fails on the first match of the consequent
        if (ha[s] && hb[s+1]) begin
          tick = s + 1;
          pass = 0;
        end
        else if (ha[s]) begin
          tick = s + 2;
          pass = !hb[s+2];
        end
      end
      3: pass = !hb[s];
      default: begin
        // A vacuous success of the implication fails the negation
        tick = s + 1;
        pass = ha[s+1] && !hb[s+1];
      end
    endcase
  endtask

  always @(posedge clk) begin
    cyc <= cyc + 1;
    crc <= {crc[62:0], crc[63] ^ crc[2] ^ crc[0]};
  end

  // Check the actions of the attempts resolving before tick NCYC
  task automatic check_actions();
    for (int i = 0; i < NPROP; ++i) begin
      int expPasses = 0;
      int expFails = 0;
      for (int s = 0; s < NCYC; ++s) begin
        bit pass;
        bit vacuous;
        int tick;
        expect_attempt(i, s, pass, vacuous, tick);
        if (tick >= NCYC) continue;
        if (!pass) ++expFails;
        else if (!vacuous || tick < OFF) ++expPasses;
      end
      `checkd(passes[i], expPasses);
      // Matches of two attempts on one tick fail property 2 once
      if (i != 2) `checkd(fails[i], expFails);
    end
  endtask

  // Between ticks, after the actions of the previous tick
  always @(negedge clk) begin
    if (cyc == OFF) $assertvacuousoff;
    if (cyc == NCYC) begin
      check_actions();
      `checkd(passes[0], 105);
      `checkd(fails[0], 55);
      `checkd(passes[1], 93);
      `checkd(fails[1], 67);
      `checkd(passes[2], 82);
      `checkd(passes[3], 75);
      `checkd(fails[3], 85);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
