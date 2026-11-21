// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module t (
    input clk
);

  // Large memories initialized and reset by a default, not by a value per element
  logic [30:0] mem[65536] = '{default: '0};
  logic [6:0] mem2[256][300] = '{default: '{default: '0}};
  logic [30:0] memk[2:301] = '{2: 31'h12, 301: 31'h34, default: 31'h5a5a};
  logic [6:0] few[3:1] = '{default: 7'h11};
  logic [30:0] memd[65538:3] = '{3: 31'h7, default: '0};
  int cyc = 0;

  always_ff @(posedge clk) begin
    cyc <= cyc + 1;
    mem[cyc[15:0]] <= 31'(cyc + 1);
    memd[cyc + 4] <= 31'(cyc + 2);
    mem2[cyc[7:0]][cyc % 300] <= 7'(cyc + 1);
    memk[cyc + 3] <= 31'(cyc);
    if (cyc == 0) begin
      `checkh(mem[0], 31'h0);
      `checkh(mem[65535], 31'h0);
      `checkh(mem2[255][299], 7'h0);
      `checkh(memk[2], 31'h12);
      `checkh(memk[3], 31'h5a5a);
      `checkh(memk[300], 31'h5a5a);
      `checkh(memk[301], 31'h34);
      `checkh(few[1], 7'h11);
      `checkh(memd[3], 31'h7);
      `checkh(memd[4], 31'h0);
      `checkh(memd[65538], 31'h0);
    end
    else if (cyc == 5) begin
      `checkh(mem[4], 31'h5);
      `checkh(mem[5], 31'h0);
      `checkh(mem2[4][4], 7'h5);
      `checkh(memk[7], 31'h4);
      `checkh(memd[8], 31'h6);
      `checkh(memd[3], 31'h7);
      mem <= '{default: '0};
      mem2 <= '{default: '{default: '0}};
      memk <= '{default: 31'(cyc)};
    end
    else if (cyc == 6) begin
      `checkh(mem[4], 31'h0);
      `checkh(mem2[4][4], 7'h0);
      `checkh(memk[301], 31'h5);
    end
    else if (cyc == 9) begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end

endmodule
