// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define checks(gotv,expv) do if ((gotv) != (expv)) begin $write("%%Error: %s:%0d:  got=\"%s\" exp=\"%s\"\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Hierarchical references relative to a generate block, from code that later
// passes move out of the block (IEEE 1800-2023 23.8). Each count is made once
// in 'sub' on its own 'x', and once in the generate block on 'u.x'. Block 'h'
// has instances of one module, compared with the equally driven ones in 'g'.

// verilog_format: off
`define COUNTERS(X) \
    int npast = 0, nrose = 0, nstable = 0, nimpl = 0, ndelay = 0, nrep = 0; \
    int ncover = 0, nfuture = 0, nseq = 0, nfork = 0, nstb = 0, ncls = 0, ncov = 0; \
    sequence s_x(logic b); @(posedge t.clk) b; endsequence \
    class C; function int get(); return int'(X); endfunction endclass \
    C c = new; \
    covergroup cg @(posedge t.clk); cp : coverpoint X {bins b[] = {[0 : 7]};} endgroup \
    cg cov = new; \
    always @(negedge t.clk) ncov <= int'(cov.get_inst_coverage()); \
    always @(posedge t.clk) if (t.cyc > 1 && $past(X) != X) npast++; \
    always @(posedge t.clk) if ($rose(X[0])) nrose++; \
    always @(posedge t.clk) if (c.get() == 2) ncls++; \
    assert property (@(posedge t.clk) t.cyc > 1 && $stable(X)) nstable++; else; \
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
`define CHECKS(A, B) \
    `checkd(A.npast, B.npast); \
    `checkd(A.nrose, B.nrose); \
    `checkd(A.ncls, B.ncls); \
    `checkd(A.nstable, B.nstable); \
    `checkd(A.nimpl, B.nimpl); \
    `checkd(A.ndelay, B.ndelay); \
    `checkd(A.nrep, B.nrep); \
    `checkd(A.ncover, B.ncover); \
    `checkd(A.nfuture, B.nfuture); \
    `checkd(A.nseq, B.nseq); \
    `checkd(A.nfork, B.nfork); \
    `checkd(A.nstb, B.nstb); \
    `checkd(A.ncov, B.ncov)
// verilog_format: on

module sub #(
    parameter int ID = 0
) (
    input int div
);
  logic [7:0] x = 0;
  always @(posedge t.clk) x <= 8'(t.cyc / div);
  `COUNTERS(x)
  bit s;
  clocking scb @(posedge t.clk);
    output s;
  endclocking
endmodule

module t;
  logic clk = 0;
  int cyc = 0;
  always #5 clk = ~clk;
  always @(posedge clk) cyc <= cyc + 1;

  global clocking @(posedge clk);
  endclocking

  // Instances with different parameters, so different modules
  for (genvar i = 0; i < 2; ++i) begin : g
    sub #(.ID(i)) u (.div(1 + 2 * i));
    `COUNTERS(u.x)
    // Synchronous drive of the value last driven, after a procedural assignment
    string slog;
    always @(u.s) slog = {slog, $sformatf("%0d@%0d ", u.s, $time)};
    initial begin
      @(posedge clk);
      u.scb.s <= 1;
      #2 u.s = 0;
      @(posedge clk);
      u.scb.s <= 1;
    end
  end
  // Instances of the same module, driven like those in 'g'
  for (genvar i = 0; i < 2; ++i) begin : h
    sub u (.div(1 + 2 * i));
    `COUNTERS(u.x)
  end

  initial begin
    #200;
    `CHECKS(g[0], g[0].u)
    `CHECKS(g[1], g[1].u)
    `CHECKS(h[0], g[0])
    `CHECKS(h[1], g[1])
    `checks(g[0].slog, "1@5 0@7 1@15 ");
    `checks(g[1].slog, "1@5 0@7 1@15 ");
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
