// DESCRIPTION: Verilator: Repeated broad assertion-control selections
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module leaf(input bit clk, output int reports);
  always @(posedge clk) begin
    checked: assert (!clk) else reports++;
  end
endmodule

module mid(input bit clk, output wire [31:0] reports);
  leaf u(.clk, .reports);
endmodule

module t;
  bit clk;
  wire [31:0] selected;
  wire [31:0] peer;
  wire [31:0] deeper;
  if (1) begin : hub
    for (genvar i = 0; i < 1; ++i) begin : bank
      leaf u(.clk, .reports(selected));
    end
  end
  leaf other(.clk, .reports(peer));
  mid deep(.clk, .reports(deeper));

  task automatic tick;
    #1 clk = 1;
    #1 clk = 0;
  endtask

  initial begin
    $assertoff(0, $root.t.hub);
    tick();
    `checkd(selected, 0);
    `checkd(peer, 1);
    `checkd(deeper, 1);
    $asserton(0, $root.t.hub);
    tick();
    `checkd(selected, 1);
    `checkd(peer, 2);
    `checkd(deeper, 2);
    $assertoff(2);
    tick();
    `checkd(selected, 1);
    `checkd(peer, 2);
    `checkd(deeper, 3);
    $asserton(2);
    tick();
    `checkd(selected, 2);
    `checkd(peer, 3);
    `checkd(deeper, 4);
    $assertoff(0, $root.t.hub.bank[0], $root.t.other);
    tick();
    `checkd(selected, 2);
    `checkd(peer, 3);
    `checkd(deeper, 5);
    $asserton(0, $root.t.hub.bank[0], $root.t.other);
    tick();
    `checkd(selected, 3);
    `checkd(peer, 4);
    `checkd(deeper, 6);
    $display("*-* All Finished *-*");
    $finish;
  end
endmodule
