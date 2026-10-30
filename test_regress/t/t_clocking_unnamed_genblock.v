// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

// Unnamed default and global clocking blocks, in a named generate block and
// directly in a module, referenced hierarchically
module t (
  input clk
);
  int cyc = 0;

  sub_gen u_gen (.clk(clk), .cyc(cyc));
  sub u_sub (.clk(clk), .cyc(cyc));

  always @(posedge clk) begin
    cyc <= cyc + 1;
    if (cyc == 20) begin
      // Fails at cyc 1, 4, ..., 19
      `checkd(u_gen.g.fails, 7);
      `checkd(u_gen.g.n, 3);
      `checkd(u_gen.g.m, 4);
      `checkd(u_sub.fails, 7);
      `checkd(u_sub.n, 3);
      `checkd(u_sub.m, 4);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule

module sub_gen (
  input clk,
  input int cyc
);
  if (1) begin : g
    int fails = 0;
    int n, m;
    global clocking @(posedge clk);
    endclocking
    default clocking @(negedge clk);
    endclocking
    assert property (cyc % 3 != 1)
    else fails++;
    initial begin
      @(posedge clk);
      repeat (3) @($global_clock);
      n = cyc;
      ##2;
      m = cyc;
    end
  end
endmodule

module sub (
  input clk,
  input int cyc
);
  int fails = 0;
  int n, m;
  global clocking @(posedge clk);
  endclocking
  default clocking @(negedge clk);
  endclocking
  assert property (cyc % 3 != 1)
  else fails++;
  initial begin
    @(posedge clk);
    repeat (3) @($global_clock);
    n = cyc;
    ##2;
    m = cyc;
  end
endmodule
