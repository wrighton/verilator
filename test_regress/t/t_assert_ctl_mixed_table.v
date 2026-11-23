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
`ifdef VIA_COHORTS
interface bank_group #(parameter int N = `N)
                     (input bit clk, input bit good, output wire [31:0] reports [N]);
`else
interface bank_group #(parameter int N = 4)
                     (input bit clk, input bit good, output wire [31:0] reports [N]);
`endif
  if (1) begin : payload
    for (genvar i = 0; i < N; ++i) begin : slots
      bank_leaf u (.clk, .good, .reports(reports[i]));
    end
  end
endinterface
`endif

module caller (input bit clk, input bit good, input bit off, output int reports
`ifdef VIA_COHORTS
               , input int level
`endif
`ifdef VIA_PORT
               , bank_group port_bank
`endif
`ifdef VIA_COHORTS
               , bank_group other_bank
`endif
);
  always @(posedge clk) begin
    local_check : assert (good) else reports++;
  end
`ifdef VIA_COHORTS
`ifdef REVERSE_COHORT
  always @(posedge off) $assertoff(level, other_bank.payload.slots[0].u, port_bank.payload.slots[0].u,
                                 other_bank.payload, port_bank.payload,
`else
  always @(posedge off) $assertoff(level, port_bank.payload, other_bank.payload,
                                 port_bank.payload.slots[0].u, other_bank.payload.slots[0].u,
`endif
`ifdef VIA_COMMON
                                 $root.t.common.payload,
`endif
                                 local_check);
`elsif VIA_PORT
  always @(posedge off) $assertoff(0, port_bank.payload, local_check);
`else
  always @(posedge off) $assertoff(0, $root.t.bank, local_check);
`endif
endmodule

`ifdef VIA_FORWARD
module relay_inner (input bit clk, input bit good, input bit [1:0] off,
                    output wire [31:0] reports [2], bank_group upstream
`ifdef VIA_COHORTS
                    , input int level, bank_group also_upstream
`endif
);
  for (genvar i = 0; i < 2; ++i) begin : callers
    caller u (.clk, .good, .off(off[i]), .reports(reports[i]), .port_bank(upstream)
`ifdef VIA_COHORTS
              , .level, .other_bank(also_upstream)
`endif
    );
  end
endmodule

module relay_outer (input bit clk, input bit good, input bit [1:0] off,
                    output wire [31:0] reports [2], bank_group forwarded
`ifdef VIA_COHORTS
                    , input int level, bank_group also_forwarded
`endif
);
  if (1) begin : bridge
    relay_inner u (.clk, .good, .off, .reports, .upstream(forwarded)
`ifdef VIA_COHORTS
                   , .level, .also_upstream(also_forwarded)
`endif
    );
  end
endmodule
`endif

`ifdef VIA_COHORTS
module bank_host (input bit clk, input bit good, input bit [`N-1:0] off, input int level,
                  output wire [31:0] local_reports [`N], output wire [31:0] bank_reports [2][`N]);
  bank_group bank (.clk, .good, .reports(bank_reports[0]));
  bank_group other (.clk, .good, .reports(bank_reports[1]));
  for (genvar i = 0; i < `N/2; ++i) begin : relays
    relay_outer u (.clk, .good, .off(off[2*i+:2]), .reports(local_reports[2*i+:2]),
                   .forwarded(bank), .level, .also_forwarded(other));
  end
endmodule

module t;
  localparam int N = `N;
  bit clk;
  bit good;
  bit [N-1:0] off [2];
  bit [1:0] fallback_off;
  int level;
  wire [31:0] local_reports [2][N];
  wire [31:0] fallback_reports [2];
  wire [31:0] bank_reports [3][2][N];
`ifdef VIA_COMMON
  wire [31:0] common_reports [N+1];
  bank_group #(.N(N+1)) common (.clk, .good, .reports(common_reports));
`endif
  // Each host's callers share two banks, neither shared with the other host.
  for (genvar b = 0; b < 2; ++b) begin : hosts
    bank_host u (.clk, .good, .off(off[b]), .level, .local_reports(local_reports[b]),
                 .bank_reports(bank_reports[b]));
  end
  // The same callers also receive interfaces through hierarchical pin references.
  if (1) begin : fallback
    bank_group bank (.clk, .good, .reports(bank_reports[2][0]));
    bank_group other (.clk, .good, .reports(bank_reports[2][1]));
  end
  relay_outer fallback_relay (.clk, .good, .off(fallback_off), .reports(fallback_reports),
                              .forwarded(fallback.bank), .level, .also_forwarded(fallback.other));

  task automatic tick;
    #1 clk = 1;
    #1 clk = 0;
  endtask

  initial begin
    // At level 1, only the directly named leaf in each bank and the caller's own site stop.
    level = 1;
    #1 off[0][0] = 1;
    tick();
    foreach (bank_reports[b, k, i]) `checkd(bank_reports[b][k][i], b == 0 && i == 0 ? 0 : 1);
    foreach (local_reports[b, i]) `checkd(local_reports[b][i], b == 0 && i == 0 ? 0 : 1);
    foreach (fallback_reports[i]) `checkd(fallback_reports[i], 1);
`ifdef VIA_COMMON
    foreach (common_reports[i]) `checkd(common_reports[i], 1);
`endif

    // With no depth limit, a caller in the second host stops every site in both its banks.
    level = 0;
    #1 off[1][N-1] = 1;
    tick();
    foreach (bank_reports[b, k, i]) begin
      `checkd(bank_reports[b][k][i], b == 0 && i == 0 ? 0 : b == 1 ? 1 : 2);
    end
    foreach (local_reports[b, i]) begin
      `checkd(local_reports[b][i], b == 0 && i == 0 ? 0 : b == 1 && i == N-1 ? 1 : 2);
    end
    foreach (fallback_reports[i]) `checkd(fallback_reports[i], 2);
`ifdef VIA_COMMON
    foreach (common_reports[i]) `checkd(common_reports[i], 1);
`endif

    // Another caller in the first host and the hierarchical route each stop both their banks.
    #1;
    off[0][1] = 1;
    fallback_off[0] = 1;
    tick();
    foreach (bank_reports[b, k, i]) begin
      `checkd(bank_reports[b][k][i], b == 0 && i == 0 ? 0 : b == 1 ? 1 : 2);
    end
    foreach (local_reports[b, i]) begin
      `checkd(local_reports[b][i], b == 0 && i == 0 ? 0 : b == 0 && i == 1 ? 2 :
              b == 1 && i == N-1 ? 1 : 3);
    end
    foreach (fallback_reports[i]) `checkd(fallback_reports[i], i == 0 ? 2 : 3);
`ifdef VIA_COMMON
    foreach (common_reports[i]) `checkd(common_reports[i], 1);
`endif
    $display("*-* All Finished *-*");
    $finish;
  end
endmodule
`else
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
`endif
