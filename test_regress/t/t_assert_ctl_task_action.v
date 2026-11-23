// DESCRIPTION: Verilator: Scoped control in a concurrent assertion action in a task
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module reporting(input bit clk, input bit good, output int reports);
  always @(posedge clk) begin
    checked: assert (good) else reports++;
  end
endmodule

module t;
  bit clk;
  bit good;
  int effect = 4;
  int levels = 1;
  wire [31:0] selected_reports;
  wire [31:0] peer_reports;
  reporting u(.clk, .good, .reports(selected_reports));
  reporting peer(.clk, .good, .reports(peer_reports));

  task automatic install;
    assert property (@(posedge clk) good)
      else $assertcontrol(effect, 2, 1, levels, u);
  endtask

  initial begin
    install();
    // Both instances report on the first edge. Only the peer keeps reporting.
    repeat (4) begin
      #1 clk = 1;
      #1 clk = 0;
    end
    `checkd(selected_reports, 1);
    `checkd(peer_reports, 4);
    $display("*-* All Finished *-*");
    $finish;
  end
endmodule
