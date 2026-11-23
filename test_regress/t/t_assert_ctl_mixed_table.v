// DESCRIPTION: Verilator: Absolute and local assertion targets in one control
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__, `__LINE__, (gotv), (expv)); `stop; end while (0);
// verilog_format: on

`ifdef VIA_PORT
interface bank_leaf (input bit clk, input bit good, output int reports);
`else
module bank_leaf (input bit clk, input bit good, output int reports);
`endif
  always @(posedge clk) begin
    bank_check : assert (good) else reports++;
  end
`ifdef VIA_PORT
endinterface
`else
endmodule
`endif

`ifdef VIA_PORT
interface bank_group (input bit clk, input bit good, output wire [31:0] reports [4]);
  if (1) begin : payload
    for (genvar i = 0; i < 4; ++i) begin : slots
      bank_leaf u (.clk, .good, .reports(reports[i]));
    end
  end
endinterface
`endif

module caller (input bit clk, input bit good, input bit off, output int reports
`ifdef VIA_PORT
               , bank_group port_bank
`endif
);
  always @(posedge clk) begin
    local_check : assert (good) else reports++;
  end
`ifdef VIA_PORT
  always @(posedge off) $assertoff(0, port_bank.payload, local_check);
`else
  always @(posedge off) $assertoff(0, $root.t.bank, local_check);
`endif
endmodule

`ifdef VIA_FORWARD
module relay_inner (input bit clk, input bit good, input bit [1:0] off,
                    output wire [31:0] reports [2], bank_group upstream);
  for (genvar i = 0; i < 2; ++i) begin : callers
    caller u (.clk, .good, .off(off[i]), .reports(reports[i]), .port_bank(upstream));
  end
endmodule

module relay_outer (input bit clk, input bit good, input bit [1:0] off,
                    output wire [31:0] reports [2], bank_group forwarded);
  if (1) begin : bridge
    relay_inner u (.clk, .good, .off, .reports, .upstream(forwarded));
  end
endmodule
`endif

module t;
  bit clk;
  bit good;
  bit [3:0] off;
  wire [31:0] local_reports [4];
  wire [31:0] bank_reports [4];
`ifdef VIA_PORT
  bank_group bank (.clk, .good, .reports(bank_reports));
`else
  if (1) begin : bank
    for (genvar i = 0; i < 4; ++i) begin : slots
      bank_leaf u (.clk, .good, .reports(bank_reports[i]));
    end
  end
`endif
`ifdef VIA_FORWARD
  for (genvar i = 0; i < 2; ++i) begin : relays
    relay_outer u (.clk, .good, .off(off[2*i+:2]), .reports(local_reports[2*i+:2]),
                   .forwarded(bank));
  end
`else
  for (genvar i = 0; i < 4; ++i) begin : callers
    caller u (.clk, .good, .off(off[i]), .reports(local_reports[i])
`ifdef VIA_PORT
              , .port_bank(bank)
`endif
    );
  end
`endif
  initial begin
    #1 off = 4'b0001;
    #1 clk = 1;
    #1 clk = 0;
    #1 good = 1;
    #1 clk = 1;
    #1;
    foreach (bank_reports[i]) `checkd(bank_reports[i], 0);
    foreach (local_reports[i]) `checkd(local_reports[i], i == 0 ? 0 : 1);
    $display("*-* All Finished *-*");
    $finish;
  end
endmodule
