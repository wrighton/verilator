// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Hierarchical references relative to a generate block, from code that later
// passes move out of the block (IEEE 1800-2023 23.8). Each count is made once
// in 'sub' on its own 'x', and once in the generate block on 'u.x'.

// verilog_format: off
`define COUNTERS(X) \
    int npast = 0, nrose = 0, nstable = 0, nimpl = 0, ndelay = 0, nrep = 0; \
    int ncover = 0, nfuture = 0, nseq = 0, nfork = 0, nstb = 0, ncls = 0, ncov = 0; \
    sequence s_x(logic b); @(posedge t.clk) b; endsequence \
    class C; function int get(); return int'(X); endfunction endclass \
    C c = new; \
    covergroup cg @(posedge t.clk); cp : coverpoint X {bins b[] = {[0 : 7]};} endgroup \
    cg cov = new; \
    always @(negedge t.clk) ncov <= int'(cov.get_coverage()); \
    always @(posedge t.clk) if (t.cyc > 1 && $past(X) != X) npast++; \
    always @(posedge t.clk) if ($rose(X[0])) nrose++; \
    always @(posedge t.clk) if (c.get() == 2) ncls++; \
    assert property (@(posedge t.clk) t.cyc > 1 && $stable(X)) nstable++; \
    assert property (@(posedge t.clk) X[0] |=> X[1]) nimpl++; else; \
    assert property (@(posedge t.clk) X[0] |-> ##1 X[1]) ndelay++; else; \
    assert property (@(posedge t.clk) X[1] [*2] |-> 1) nrep++; \
    cover property (@(posedge t.clk) X[0] ##1 X[0]) ncover++; \
    assert property (@(posedge t.clk) $future_gclk(X) == X) nfuture++; else; \
    initial forever @(s_x(X[0])) nseq++; \
    initial begin \
      static int k = 10; \
      fork begin automatic int a = k; \
        @(posedge t.clk iff X == 3) nfork = a + int'(X); \
      end join_none \
    end \
    always @(posedge t.clk) $strobe("%0d", (nstb += int'(X)));
// verilog_format: on

module sub #(
    parameter int ID = 0
);
  logic [7:0] x = 0;
  always @(posedge t.clk) x <= (ID == 0) ? 8'(t.cyc) : 8'(t.cyc / 3);
  `COUNTERS(x)
endmodule

module t;
  logic clk = 0;
  int cyc = 0;
  always #5 clk = ~clk;
  always @(posedge clk) cyc <= cyc + 1;

  global clocking @(posedge clk);
  endclocking

  for (genvar i = 0; i < 2; ++i) begin : g
    sub #(.ID(i)) u ();
    `COUNTERS(u.x)
  end

  initial begin
    #200;
    `checkd(g[0].npast, g[0].u.npast);
    `checkd(g[1].npast, g[1].u.npast);
    `checkd(g[0].nrose, g[0].u.nrose);
    `checkd(g[1].nrose, g[1].u.nrose);
    `checkd(g[0].ncls, g[0].u.ncls);
    `checkd(g[1].ncls, g[1].u.ncls);
    `checkd(g[0].nstable, g[0].u.nstable);
    `checkd(g[1].nstable, g[1].u.nstable);
    `checkd(g[0].nimpl, g[0].u.nimpl);
    `checkd(g[1].nimpl, g[1].u.nimpl);
    `checkd(g[0].ndelay, g[0].u.ndelay);
    `checkd(g[1].ndelay, g[1].u.ndelay);
    `checkd(g[0].nrep, g[0].u.nrep);
    `checkd(g[1].nrep, g[1].u.nrep);
    `checkd(g[0].ncover, g[0].u.ncover);
    `checkd(g[1].ncover, g[1].u.ncover);
    `checkd(g[0].nfuture, g[0].u.nfuture);
    `checkd(g[1].nfuture, g[1].u.nfuture);
    `checkd(g[0].nseq, g[0].u.nseq);
    `checkd(g[1].nseq, g[1].u.nseq);
    `checkd(g[0].nfork, g[0].u.nfork);
    `checkd(g[1].nfork, g[1].u.nfork);
    `checkd(g[0].nstb, g[0].u.nstb);
    `checkd(g[1].nstb, g[1].u.nstb);
    `checkd(g[0].ncov, g[0].u.ncov);
    `checkd(g[1].ncov, g[1].u.ncov);
    $display("%0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d", g[0].npast, g[0].nrose,
             g[0].ncls, g[0].nstable, g[0].nimpl, g[0].ndelay, g[0].nrep,
             g[0].ncover, g[0].nfuture, g[0].nseq, g[0].nfork, g[0].nstb);
    $display("%0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d", g[1].npast, g[1].nrose,
             g[1].ncls, g[1].nstable, g[1].nimpl, g[1].ndelay, g[1].nrep,
             g[1].ncover, g[1].nfuture, g[1].nseq, g[1].nfork, g[1].nstb);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
