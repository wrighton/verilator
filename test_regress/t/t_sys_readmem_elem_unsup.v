// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;
  typedef logic [7:0] row_t[0:1];
  typedef row_t bank_t[];
  logic [7:0] mem[5:0];
  logic [7:0] mem2[2][6];
  logic [7:0] mem3[3:0][0:3];
  logic [7:0] queue_of_fixed[$][4];
  logic [7:0] dyn_of_fixed[][4];
  logic [64:0] dyn_of_wide[][0:1];
  logic [7:0] assoc_of_fixed[int][4];
  logic [7:0] dyn_row[2][];
  logic [7:0] assoc_row[2][int];
  bank_t bank[0:1];
  logic [7:0] q[$];
  logic [7:0] queue_row[2][$];
  int i = 1;
  initial begin
    $readmemh("t/t_sys_readmem_h.mem", mem[3:2]);
    $readmemb("t/t_sys_readmem_b.mem", mem2[i][1+:2]);
    $readmemh("t/t_sys_readmem_h.mem", mem3[1:0][1]);
    $readmemh("t/t_sys_readmem_h.mem", queue_of_fixed[0:1][1]);
    $readmemh("t/t_sys_readmem_h.mem", queue_of_fixed[i]);
    $readmemh("t/t_sys_readmem_h.mem", dyn_of_fixed[i]);
    $readmemh("t/t_sys_readmem_h.mem", dyn_of_wide[i]);
    $readmemh("t/t_sys_readmem_h.mem", assoc_of_fixed[i]);
    $readmemh("t/t_sys_readmem_h.mem", dyn_row[i]);
    $readmemh("t/t_sys_readmem_h.mem", assoc_row[i]);
    $readmemh("t/t_sys_readmem_h.mem", bank[0]);
    $readmemh("t/t_sys_readmem_h.mem", q[1:2]);
    $readmemh("t/t_sys_readmem_h.mem", queue_row[i]);
  end
endmodule
