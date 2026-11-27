// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv, expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// A property operator over an operand resolving 100 ticks after its attempt start, so 101
// attempts are in flight, more than a machine word holds. With 300 ticks the property is over
// the width limit.

module t (
    input clk
);
  localparam int NCYC = 400;
  localparam int DELAY = 100;

  integer cyc = 0;
  reg [63:0] crc = 64'h5aef0c8d_d70a4497;

  wire a = crc[0];
  wire b = crc[9] | crc[12];
  wire c = crc[18];
  wire d = crc[27] | crc[30];

  bit ha[NCYC];
  bit hb[NCYC];
  bit hc[NCYC];
  bit hd[NCYC];
  always @(posedge clk) begin
    ha[cyc] = a;
    hb[cyc] = b;
    hc[cyc] = c;
    hd[cyc] = d;
  end

  int passes = 0;
  int fails = 0;
  int overLimitFails = 0;

  // verilog_format: off
  assert property (@(posedge clk) (a |-> ##DELAY b) and (c |-> d)) ++passes;
  else ++fails;
  assert property (@(posedge clk) (a |-> ##300 b) and (c |-> d))
  else ++overLimitFails;
  // verilog_format: on

  // Check the actions of the attempts resolving by tick last
  task automatic check_actions(int last);
    int expPasses = 0;
    int expFails = 0;
    for (int s = 0; s <= last; ++s) begin
      if (hc[s] && !hd[s]) ++expFails;
      else if (!ha[s]) ++expPasses;
      else if (s + DELAY <= last) begin
        if (hb[s+DELAY]) ++expPasses;
        else ++expFails;
      end
    end
    `checkd(passes, expPasses);
    `checkd(fails, expFails);
  endtask

  always @(posedge clk) begin
    cyc <= cyc + 1;
    crc <= {crc[62:0], crc[63] ^ crc[2] ^ crc[0]};
  end

  always @(negedge clk) begin
    if (cyc == NCYC) begin
      check_actions(NCYC - 1);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
