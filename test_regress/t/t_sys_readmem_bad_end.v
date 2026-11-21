// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2003 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define STRINGIFY(x) `"x`"
// verilog_format: on

module t;

  reg [175:0] hex[15:0];

  integer i;
  integer fd;
  string filename;

  initial begin
    // No warning as has addresses
    $readmemh("t/t_sys_readmem_bad_end2.mem", hex, 0, 15);
    // Warning as wrong end address
    $readmemh("t/t_sys_readmem_bad_end.mem", hex, 0, 15);

    filename = {`STRINGIFY(`TEST_OBJ_DIR), "/dat.mem"};
    fd = $fopen(filename, "w");
    $fdisplay(fd, "11 22 33");
    $fclose(fd);

    // Warning as file has more data words than the range, and loading stops at finish
    foreach (hex[i]) hex[i] = 'hff;
    $readmemh(filename, hex, 1, 2);
    `checkh(hex[0], 'hff);
    `checkh(hex[1], 'h11);
    `checkh(hex[2], 'h22);
    `checkh(hex[3], 'hff);
    `checkh(hex[4], 'hff);
    `checkh(hex[15], 'hff);
    // Same when descending
    foreach (hex[i]) hex[i] = 'hff;
    $readmemh(filename, hex, 6, 5);
    `checkh(hex[0], 'hff);
    `checkh(hex[3], 'hff);
    `checkh(hex[4], 'hff);
    `checkh(hex[5], 'h22);
    `checkh(hex[6], 'h11);
    `checkh(hex[7], 'hff);
    `checkh(hex[8], 'hff);
    `checkh(hex[15], 'hff);

    // Warning as address in file is outside the range, and loading stops
    fd = $fopen(filename, "w");
    $fdisplay(fd, "11");
    $fdisplay(fd, "@5");
    $fdisplay(fd, "22");
    $fclose(fd);
    foreach (hex[i]) hex[i] = 'hff;
    $readmemh(filename, hex, 1, 2);
    `checkh(hex[0], 'hff);
    `checkh(hex[1], 'h11);
    `checkh(hex[2], 'hff);
    `checkh(hex[4], 'hff);
    `checkh(hex[5], 'hff);
    `checkh(hex[6], 'hff);
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
