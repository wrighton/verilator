// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module sub;
endmodule

// IEEE 1800-2023 27.6: An implicit 'genblk<n>' name that conflicts with an
// explicitly declared name gets leading zeros until it does not conflict
module t;
  parameter genblk2 = 0;
  parameter type genblk13 = int;

  // 1
  if (genblk2) begin
    int a = 0;
  end else begin
    int b = 11;
  end
  // 2: genblk02 as parameter genblk2
  if (genblk2) begin
    int a = 0;
  end else begin
    int b = 12;
  end
  // 3: genblk03 as wire genblk3, declared later
  if (1) begin
    int c = 13;
  end
  // 4: genblk004 as variable genblk4 and generate block genblk04
  for (genvar i = 0; i < 2; ++i) begin
    int d = i;
  end
  // 5: genblk005 as function genblk5 and instance genblk05
  case (genblk2)
    0: begin
      int e = 15;
    end
    default: begin
      int e = 0;
    end
  endcase
  // 6
  if (1) begin : genblk04
    int f = 16;
  end
  // 7: genblk07 as typedef genblk7
  if (0) begin
    int g = 0;
  end else if (1) begin
    int g = 17;
  end
  // 8: genblk08 as procedural block genblk8
  if (1) begin
    int h = 18;
  end
  // 9: declares genblk10 in an else-if branch
  if (0) begin
    int g = 0;
  end else if (0) begin : genblk10
    int g = 0;
  end else begin
    int g = 19;
  end
  // 10: genblk010 as generate block genblk10
  if (1) begin
    int n = 20;
  end
  // 11: Each generate block is a separate scope
  if (1) begin : named
    wire genblk1 = 1'b1;
    if (1) begin
      int p = 21;
    end
  end
  // 12
  for (genvar i = 0; i < 1; ++i) begin : loop
    wire genblk1 = 1'b1;
    if (1) begin
      int q = 22;
    end
  end
  // 13: genblk013 as type parameter genblk13
  if (1) begin
    genblk13 r = 23;
  end

  wire genblk3 = 1'b1;
  logic genblk4 = 1'b0;
  function automatic int genblk5();
    return 5;
  endfunction
  sub genblk05 ();
  typedef int genblk7;

  initial begin : genblk8
    `checkd(genblk2, 0);
    `checkd(genblk3, 1'b1);
    `checkd(genblk4, 1'b0);
    `checkd(genblk5(), 5);
    `checkd(genblk1.b, 11);
    `checkd(genblk02.b, 12);
    `checkd(genblk03.c, 13);
    `checkd(genblk004[1].d, 1);
    `checkd(genblk005.e, 15);
    `checkd(genblk04.f, 16);
    `checkd(genblk07.g, 17);
    `checkd(genblk08.h, 18);
    `checkd(genblk9.g, 19);
    `checkd(genblk010.n, 20);
    `checkd(named.genblk01.p, 21);
    `checkd(loop[0].genblk01.q, 22);
    `checkd(genblk013.r, 23);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
