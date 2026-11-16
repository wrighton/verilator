// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2003 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

`define STRINGIFY(x) `"x`"

module t;

  reg [175:0] hex[15:0];

  integer i;

  initial begin
    // No warning as has addresses
    $readmemh("t/t_sys_readmem_bad_end2.mem", hex, 0, 15);
    // Warning as wrong end address
    $readmemh("t/t_sys_readmem_bad_end.mem", hex, 0, 15);
    // Warning as more words than the range, which are not loaded
    foreach (hex[i]) hex[i] = 176'hff;
    $readmemh("t/t_sys_readmem_bad_end.mem", hex, 14, 15);
    `checkh(hex[13], 176'hff);
    `checkh(hex[14], 176'h00);
    `checkh(hex[15], 176'h01);
    $readmemh("t/t_sys_readmem_bad_end.mem", hex, 1, 0);
    `checkh(hex[2], 176'hff);
    `checkh(hex[1], 176'h00);
    `checkh(hex[0], 176'h01);
    $readmemh("t/t_sys_readmem_bad_end.mem", hex, 6, 7);
    `checkh(hex[5], 176'hff);
    `checkh(hex[6], 176'h00);
    `checkh(hex[7], 176'h01);
    `checkh(hex[8], 176'hff);
    check_addresses();
    $write("*-* All Finished *-*\n");
    $finish;
  end

  // Address directives in the file within the range
  task automatic check_addresses();
    int fd;
    string filename;
    logic [6:0] mem[0:7];

    filename = {`STRINGIFY(`TEST_OBJ_DIR), "/reenter.mem"};
    fd = $fopen(filename, "w");
    $fdisplay(fd, "@2 22 33 @0 11");
    $fclose(fd);
    foreach (mem[i]) mem[i] = 7'h7f;
    $readmemh(filename, mem, 0, 3);
    `checkh(mem[0], 7'h11);
    `checkh(mem[1], 7'h7f);
    `checkh(mem[2], 7'h22);
    `checkh(mem[3], 7'h33);
    // Following words beyond the finish address are not loaded, without a warning as the
    // file has addresses
    filename = {`STRINGIFY(`TEST_OBJ_DIR), "/beyond.mem"};
    fd = $fopen(filename, "w");
    $fdisplay(fd, "@2 22 33 44");
    $fclose(fd);
    foreach (mem[i]) mem[i] = 7'h7f;
    $readmemh(filename, mem, 0, 3);
    `checkh(mem[3], 7'h33);
    `checkh(mem[4], 7'h7f);
    // A file that fills the range exactly, ending without a newline, gives no warning
    filename = {`STRINGIFY(`TEST_OBJ_DIR), "/exact.mem"};
    fd = $fopen(filename, "w");
    $fwrite(fd, "01 02");
    $fclose(fd);
    foreach (mem[i]) mem[i] = 7'h7f;
    $readmemh(filename, mem, 1, 0);
    `checkh(mem[1], 7'h01);
    `checkh(mem[0], 7'h02);
    $readmemh(filename, mem, 4, 5);
    `checkh(mem[4], 7'h01);
    `checkh(mem[5], 7'h02);
    `checkh(mem[6], 7'h7f);
  endtask
endmodule
