// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Independent clocked processes, each firing its own event
module t;
  logic clk = 0;
  always #5 clk = ~clk;

  logic [31:0] a[16] = '{default: 32'd1};
  int fired_a = 0;
  event ea;
  always_ff @(posedge clk) begin
    automatic logic [31:0] t = a[15];
    for (int i = 0; i < 16; ++i) begin
      t = t * 32'd1103515245 + a[i] + i;
      a[i] <= t;
    end
    if (t[4]) begin
      fired_a <= fired_a + 1;
      ->ea;
    end
  end
  int got_a = 0;
  initial forever begin
    @ea;
    ++got_a;
  end

  logic [31:0] b[16] = '{default: 32'd7};
  int fired_b = 0;
  event eb;
  always_ff @(posedge clk) begin
    automatic logic [31:0] t = b[15];
    for (int i = 0; i < 16; ++i) begin
      t = t * 32'd22695477 + b[i] + i;
      b[i] <= t;
    end
    if (t[4]) begin
      fired_b <= fired_b + 1;
      ->eb;
    end
  end
  int got_b = 0;
  initial forever begin
    @eb;
    ++got_b;
  end

  int cyc = 0;
  always @(posedge clk) begin
    cyc <= cyc + 1;
    `checkd(got_a, fired_a);
    `checkd(got_b, fired_b);
    if (cyc == 99) begin
      `checkd(fired_a, 50);
      `checkd(fired_b, 45);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
