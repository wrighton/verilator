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

  localparam int N = 13;
  // $rtoi truncates toward zero and keeps the low 32 bits, as a cast of the
  // truncated value to int does; NaN and infinities give 0
  localparam real VALS[N] = '{
      1e20,
      -1e20,
      4294967297.75,
      -4294967297.75,
      2147483648.5,
      -2147483649.0,
      2147483647.9,
      -2147483648.9,
      1e300,
      -0.5,
      $bitstoreal(64'h7ff8000000000000),  // NaN
      $bitstoreal(64'h7ff0000000000000),  // +Inf
      $bitstoreal(64'hfff0000000000000)  // -Inf
  };
  localparam int EXPS[N] = '{
      32'h63100000,
      32'h9cf00000,
      32'h00000001,
      32'hffffffff,
      32'h80000000,
      32'h7fffffff,
      32'h7fffffff,
      32'h80000000,
      0,
      0,
      0,
      0,
      0
  };

  int cyc = 0;
  always @(posedge clk) begin
    cyc <= cyc + 1;
    if (cyc < N) begin
      `checkh($rtoi(VALS[cyc]), EXPS[cyc]);
    end else begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end

  // Constant folded, and equal to the run time result
  for (genvar g = 0; g < N; ++g) begin : gen_folded
    localparam int Folded = $rtoi(VALS[g]);
    always @(posedge clk) begin
      if (cyc == g) begin
        `checkh($rtoi(VALS[cyc]), Folded);
        `checkh(Folded, EXPS[g]);
      end
    end
  end

endmodule
