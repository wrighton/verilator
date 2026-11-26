// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv, expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Property operators over implications evaluated on one tick. A vacuous
// success is a success, and runs the pass action unless vacuous passes are
// off (IEEE 1800-2023 16.12, 16.14.8, 20.11). Each attempt resolves on its own
// start tick.

module t (
    input clk
);
  localparam int NCYC = 400;
  localparam int VACUOUS_OFF_CYC = 200;

  integer cyc = 0;
  reg [63:0] crc = 64'h5aef0c8d_d70a4497;

  // Ticks 0-7 drive {a, b} = 00, 01, 10, 11 twice, then random values
  wire rnd = cyc > 7;
  wire a = rnd ? crc[0] : cyc[1];
  wire b = rnd ? crc[9] : cyc[0];
  wire c = rnd ? (crc[18] & crc[27]) : 1'b0;
  wire d = rnd && crc[36];
  wire e = rnd && crc[45];

  bit ha[NCYC];
  bit hb[NCYC];
  bit hc[NCYC];
  bit hd[NCYC];
  bit he[NCYC];
  always @(posedge clk) begin
    ha[cyc] = a;
    hb[cyc] = b;
    hc[cyc] = c;
    hd[cyc] = d;
    he[cyc] = e;
  end

  localparam int NPROP = 11;
  int passes[NPROP];
  int fails[NPROP];
  int future_fails = 0;

  global clocking @(posedge clk);
  endclocking

  // verilog_format: off
  property p_and_clocked;
    @(posedge clk) (a |-> b) and (b |-> a);
  endproperty

  assert property (@(posedge clk) (a |-> b) and (b |-> a)) ++passes[0];
  else ++fails[0];
  assert property (@(posedge clk) sync_accept_on (1'b0) (a |-> b)) ++passes[1];
  else ++fails[1];
  assert property (@(posedge clk) sync_accept_on (c) (a |-> b)) ++passes[2];
  else ++fails[2];
  assert property (@(posedge clk) sync_reject_on (c) (a |-> b)) ++passes[3];
  else ++fails[3];
  assert property (@(posedge clk) (a |-> b) or (c |-> d)) ++passes[4];
  else ++fails[4];
  assert property (@(posedge clk) (a |-> b) and (a |-> b)) ++passes[5];
  else ++fails[5];
  assert property (@(posedge clk) not ((a |-> b) and (c |-> d))) ++passes[6];
  else ++fails[6];
  assert property (@(posedge clk) a |-> ((b |-> c) and (d |-> e))) ++passes[7];
  else ++fails[7];
  assert property (p_and_clocked) ++passes[8];
  else ++fails[8];
  assert property (@(posedge clk) e |-> ((c and (a |-> b)) or ((a |-> b) and d))) ++passes[9];
  else ++fails[9];
  // A pass action suspending past the tick runs once
  assert property (@(posedge clk) (a |-> b) and (c |-> d)) begin
    automatic int start = cyc;
    ++passes[10];
    @(negedge clk);
    `checkd(cyc, start + 1);
  end
  else ++fails[10];
  // The success of an attempt is known on the next tick
  assert property (@(posedge clk) a |-> $future_gclk(b))
  else ++future_fails;
  // verilog_format: on

  // Expected success and nonvacuity of property i on tick k
  function automatic void expect_tick(int i, int k, output bit success, output bit nonvacuous);
    bit a0 = ha[k], b0 = hb[k], c0 = hc[k], d0 = hd[k], e0 = he[k];
    case (i)
      0, 8: begin
        success = (!a0 || b0) && (!b0 || a0);
        nonvacuous = a0 || b0;
      end
      1: begin
        success = !a0 || b0;
        nonvacuous = a0;
      end
      2: begin
        success = c0 || !a0 || b0;
        nonvacuous = !c0 && a0;
      end
      3: begin
        success = !c0 && (!a0 || b0);
        nonvacuous = !c0 && a0;
      end
      4: begin
        success = !a0 || b0 || !c0 || d0;
        nonvacuous = a0 || c0;
      end
      5: begin
        success = !a0 || b0;
        nonvacuous = a0;
      end
      6: begin
        success = !((!a0 || b0) && (!c0 || d0));
        nonvacuous = a0 || c0;
      end
      7: begin
        success = !a0 || ((!b0 || c0) && (!d0 || e0));
        nonvacuous = a0 && (b0 || d0);
      end
      9: begin
        success = !e0 || (c0 && (!a0 || b0)) || ((!a0 || b0) && d0);
        nonvacuous = e0;
      end
      default: begin
        success = (!a0 || b0) && (!c0 || d0);
        nonvacuous = a0 || c0;
      end
    endcase
  endfunction

  // Check the actions of every property over ticks [0, last]
  task automatic check_actions(int last);
    for (int i = 0; i < NPROP; ++i) begin
      int expPasses = 0;
      int expFails = 0;
      for (int k = 0; k <= last; ++k) begin
        bit success;
        bit nonvacuous;
        expect_tick(i, k, success, nonvacuous);
        if (!success) ++expFails;
        else if (nonvacuous || k < VACUOUS_OFF_CYC) ++expPasses;
      end
      `checkd(passes[i], expPasses);
      `checkd(fails[i], expFails);
    end
    begin
      int expFutureFails = 0;
      for (int k = 0; k < last; ++k) expFutureFails += ha[k] && !hb[k+1];
      `checkd(future_fails, expFutureFails);
    end
  endtask

  always @(posedge clk) begin
    cyc <= cyc + 1;
    crc <= {crc[62:0], crc[63] ^ crc[2] ^ crc[0]};
  end

  // Between ticks, after the actions of the previous tick
  always @(negedge clk) begin
    if (cyc == 8) begin
      `checkd(passes[0], 4);
      `checkd(fails[0], 4);
      `checkd(passes[1], 6);
      `checkd(fails[1], 2);
      check_actions(7);
    end
    else if (cyc == VACUOUS_OFF_CYC) begin
      $assertvacuousoff;
    end
    else if (cyc == NCYC - 1) begin
      check_actions(NCYC - 2);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
