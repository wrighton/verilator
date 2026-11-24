// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define STRINGIFY(x) `"x`"
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module t;
  integer fd;
  integer code;
  integer start;
  integer count;
  byte up[0:3];
  byte dn[7:4];
  reg [14:0] wd[11:9];
  int i;

  initial begin
    // File holds bytes 0, 1, 2, ...
    fd = $fopen({`STRINGIFY(`TEST_OBJ_DIR), "/t_sys_fread_range.mem"}, "r");
    foreach (up[k]) up[k] = 8'hee;
    foreach (dn[k]) dn[k] = 8'hee;
    foreach (wd[k]) wd[k] = 15'h7eee;

    // Start above the array loads nothing
    start = 100;
    code = $fread(up, fd, start, 4);
    `checkd(code, 0);
    start = 4;
    code = $fread(up, fd, start);
    `checkd(code, 0);
    start = 12;
    code = $fread(wd, fd, start, 1);
    `checkd(code, 0);
    // Start below a non-zero array LSB loads nothing
    start = 0;
    code = $fread(dn, fd, start);
    `checkd(code, 0);
    // Negative start loads nothing
    start = -1;
    code = $fread(up, fd, start, 1);
    `checkd(code, 0);
    // Zero or negative count loads nothing
    count = 0;
    code = $fread(up, fd, 1, count);
    `checkd(code, 0);
    count = -1;
    code = $fread(up, fd, 1, count);
    `checkd(code, 0);
    // Nothing was consumed or stored
    `checkd($ftell(fd), 0);
    foreach (up[k]) `checkh(up[k], 8'hee);
    foreach (dn[k]) `checkh(dn[k], 8'hee);
    foreach (wd[k]) `checkh(wd[k], 15'h7eee);

    // Count beyond the array end loads up to the end
    start = 2;
    count = 100;
    code = $fread(up, fd, start, count);
    `checkd(code, 2);
    `checkh(up[1], 8'hee);
    `checkh(up[2], 8'h00);
    `checkh(up[3], 8'h01);
    // Descending array loads toward the highest address
    start = 6;
    code = $fread(dn, fd, start, count);
    `checkd(code, 2);
    `checkh(dn[5], 8'hee);
    `checkh(dn[6], 8'h02);
    `checkh(dn[7], 8'h03);
    start = 10;
    code = $fread(wd, fd, start, count);
    `checkd(code, 4);
    `checkh(wd[9], 15'h7eee);
    `checkh(wd[10], 15'h0405);
    `checkh(wd[11], 15'h0607);
    // Integral variable ignores start and count
    start = 100;
    count = 4;
    code = $fread(i, fd, start, count);
    `checkd(code, 4);
    `checkh(i, 32'h08090a0b);

    $fclose(fd);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
