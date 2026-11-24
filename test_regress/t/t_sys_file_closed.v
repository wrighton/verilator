// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define STRINGIFY(x) `"x`"
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define checks(gotv,expv) do if ((gotv) != (expv)) begin $write("%%Error: %s:%0d:  got='%s' exp='%s'\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module t;
  // Operations on a descriptor that names no open file
  task automatic check_closed(integer fd);
    int i;
    int v;
    string s;
    byte mem[0:1];
    $fwrite(fd, "Never printed, file closed\n");
    $fflush(fd);
    i = $feof(fd);
    if (i == 0) `stop;
    i = $fgetc(fd);
    `checkd(i, -1);
    i = $ungetc(65, fd);
    `checkd(i, -1);
    i = $fgets(s, fd);
    `checkd(i, 0);
    i = $fscanf(fd, "%x", v);
    `checkd(i, -1);
    i = $fread(mem, fd);
    `checkd(i, 0);
    i = $ftell(fd);
    `checkd(i, -1);
    i = $rewind(fd);
    `checkd(i, -1);
    i = $fseek(fd, 10, 0);
    `checkd(i, -1);
    $fclose(fd);
  endtask

  initial begin
    integer fd;
    integer mcd;
    integer mcd2;
    string s;
    int i;

    // Descriptor after $fclose
    fd = $fopen({`STRINGIFY(`TEST_OBJ_DIR), "/fd.log"}, "w");
    $fclose(fd);
    check_closed(fd);

    // Multichannel descriptor after $fclose, and never-opened channels
    mcd = $fopen({`STRINGIFY(`TEST_OBJ_DIR), "/mcd.log"});
    $fclose(mcd);
    check_closed(mcd);
    check_closed(32'h6);

    // Closed channels free one slot each
    mcd = $fopen({`STRINGIFY(`TEST_OBJ_DIR), "/mcd.log"});
    mcd2 = $fopen({`STRINGIFY(`TEST_OBJ_DIR), "/mcd2.log"});
    if (mcd == 0 || mcd2 == 0 || mcd == mcd2) `stop;

    // Open channels are written when combined with never-opened ones
    $fwrite(mcd | 32'h2, "open\n");
    $fclose(mcd | mcd2 | 32'h2);
    fd = $fopen({`STRINGIFY(`TEST_OBJ_DIR), "/mcd.log"}, "r");
    i = $fgets(s, fd);
    `checks(s, "open\n");
    $fclose(fd);

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
