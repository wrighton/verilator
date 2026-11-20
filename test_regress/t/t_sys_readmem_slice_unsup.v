// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;
  logic [7:0] mem[5:0];
  logic [7:0] mem2[2][6];
  logic [7:0] mem3[3:0][0:3];
  logic [7:0] queue_of_fixed[$][4];
  int i = 1;
  initial begin
    $readmemh("t/t_sys_readmem_h.mem", mem[3:2]);
    $readmemb("t/t_sys_readmem_b.mem", mem2[i][1+:2]);
    $readmemh("t/t_sys_readmem_h.mem", mem3[1:0][1]);
    $readmemh("t/t_sys_readmem_h.mem", queue_of_fixed[0:1][1]);
  end
endmodule
