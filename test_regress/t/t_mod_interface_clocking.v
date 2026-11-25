// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2025 Antmicro
// SPDX-License-Identifier: CC0-1.0

interface axi_if;
  logic clk;
  wire rlast;
  wire rvalid;
  clocking cb @(posedge clk);
    inout rlast, rvalid;
  endclocking
  modport md1(clocking cb, inout clk, rlast, rvalid);
  modport md2(clocking cb);
endinterface

module sub (
    axi_if.md1 axi1,
    axi_if.md2 axi2
);
  initial begin
    axi1.clk = 1'b0;
    #1 axi1.clk = 1'b1;
    #1 axi1.clk = 1'b0;
    #1 axi1.clk = 1'b1;
  end
  initial begin
    @(negedge axi1.rvalid);
    $display("[%0t] rvalid==%b", $time, axi1.rvalid);
    $display("[%0t] rlast is 1: ", $time, axi1.rlast === 1);
    if (axi1.rlast === 1) $stop;
    $write("*-* All Finished *-*\n");
    $finish;
  end
  initial begin
    $display("[%0t] rvalid <= 1", $time);
    axi1.cb.rvalid <= 1'b1;
    @(posedge axi1.rvalid);
    $display("[%0t] rvalid <= 0", $time);
    axi1.cb.rvalid <= 1'b0;
    @(negedge axi1.clk);
    $display("[%0t] rlast <= 1", $time);
    axi2.cb.rlast <= 1'b1;
  end
endmodule

// Clocking block outputs whose targets are reached through an interface port
interface out_if;
  logic [3:0] v = 4'h1;
  logic [3:0] w = 4'h0;
endinterface

module out_drv (
    out_if o,
    input logic clk
);
  logic [1:0] idx = 1;
  clocking cb @(posedge clk);
    output w = o.v;
    output wi = o.w[idx];
  endclocking
  initial begin
    cb.w <= 4'h2;
    cb.wi <= 1'b1;
  end
  initial begin
    #2;
    if (o.v !== 4'h2) $stop;
    if (o.w !== 4'b0010) $stop;
  end
endmodule

module t;
  axi_if axi_vi ();
  sub i_sub (
      .axi1(axi_vi),
      .axi2(axi_vi)
  );
  out_if out_vi ();
  out_drv i_out (
      .o(out_vi),
      .clk(axi_vi.clk)
  );
endmodule
