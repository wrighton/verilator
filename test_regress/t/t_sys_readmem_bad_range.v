// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;
  logic [6:0] mem[0:7];

  initial begin
    // The file has an address beyond the finish address
    $readmemh("t/t_sys_readmem_bad_range.mem", mem, 0, 3);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
