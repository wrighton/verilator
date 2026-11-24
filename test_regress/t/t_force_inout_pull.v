// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

`timescale 1ns / 1ps

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got='h%x exp='h%x\n", `__FILE__, `__LINE__, (gotv), (expv)); `stop; end while (0)
// verilog_format: on

module leaf (
    inout wire [6:0] p,
    output wire [6:0] seen
);
  assign seen = p;
endmodule

module selected_pulls (
    inout wire [2:0] p
);
  pullup (p[2]);
  pulldown (p[0]);
endmodule

module t;
  wire [6:0] hi, lo, partial, propagated;
  for (genvar i = 0; i < 7; i++) begin : gen_pulls
    pullup (hi[i]);
    pulldown (lo[i]);
  end
  pullup (partial[2]);
  pulldown (partial[0]);
  wire [6:0] hi_seen, lo_seen, partial_seen, propagated_seen, another_seen;
  leaf high (
      .p(hi),
      .seen(hi_seen)
  );
  leaf low (
      .p(lo),
      .seen(lo_seen)
  );
  leaf selected (
      .p(partial),
      .seen(partial_seen)
  );
  leaf sibling (
      .p(propagated),
      .seen(propagated_seen)
  );
  leaf another (
      .p(propagated),
      .seen(another_seen)
  );
  selected_pulls source (.p(propagated[5:3]));

`ifdef FORCE_PULLED
  initial begin
    force high.p = '0;
    force low.p = '0;
    force selected.p = '0;
    release sibling.p;
  end
`else
  wire [6:0] plain = 7'h53;
  leaf good (
      .p(plain),
      .seen()
  );
  initial begin
    #1;
    force good.p = '0;
    #1;
    `checkh(plain, 7'h00);
    `checkh(hi_seen, 7'h7f);
    `checkh(lo_seen, 7'h00);
    `checkh(high.p === 7'bzzzzzzz, 1'b0);
    `checkh(low.p === 7'bzzzzzzz, 1'b0);
    `checkh(lo_seen === 7'bzzzzzzz, 1'b0);
    `checkh(selected.p === 7'bzzzz1z0, 1'b1);
    `checkh(partial_seen === 7'bzzzz1z0, 1'b1);
    `checkh(sibling.p === 7'bz1z0zzz, 1'b1);
    `checkh(propagated_seen === 7'bz1z0zzz, 1'b1);
    `checkh(another_seen === 7'bz1z0zzz, 1'b1);
    release good.p;
    #1;
    `checkh(plain, 7'h53);
    $write("*-* All Finished *-*\n");
    $finish;
  end
`endif
endmodule
