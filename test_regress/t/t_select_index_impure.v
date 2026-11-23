// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module t;

  int calls;
  function automatic bit [1:0] pick();
    ++calls;
    return 2'd1;
  endfunction

  initial begin
    begin
      // Test: an index beside a lane out of range is evaluated once, without a warning
      bit [2:0][3:0] lanes;
      lanes = '0;
      calls = 0;
      // verilator lint_off SELRANGE
      // verilator lint_off WIDTH
      lanes[-1][pick()] = 1'b1;
      lanes[40'h10_0000_0005][pick()] = 1'b1;
      `checkh(lanes[40'h10_0000_0005][pick()], 1'b0);
      // verilator lint_on WIDTH
      // verilator lint_on SELRANGE
      `checkh(calls, 3);
      `checkh(lanes, 12'h000);
    end

    begin
      // Test: so is a lane index beside a bit out of range
      bit [2:0][3:0] lanes;
      lanes = '0;
      calls = 0;
      // verilator lint_off SELRANGE
      // verilator lint_off WIDTH
      lanes[pick()][-1] = 1'b1;
      lanes[pick()][4] = 1'b1;
      `checkh(lanes[pick()][4], 1'b0);
      // verilator lint_on WIDTH
      // verilator lint_on SELRANGE
      `checkh(calls, 3);
      `checkh(lanes, 12'h000);
    end

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
