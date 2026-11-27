// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

`timescale 1ns / 1ps

// Test: a delayed NBA and a forked process read one variable of their task; the NBA uses the value
// when it runs (17), and the process, which starts once its parent blocks, the parent's later
// write (39)
interface wire_if;
  logic [3:0] n;
endinterface

module t;
  localparam realtime STEP = 1ns;
  class Box;
    int n;
  endclass
  Box o;
  int seen;
  task automatic drive(Box h);
    int v = 17;
    h.n <= #(STEP * 2) v;
    fork
      seen = v;
    join_none
    v = 39;
    #STEP;
  endtask
  initial begin
    o = new;
    drive(o);
    #(STEP * 3);
    `checkd(o.n, 17);
    `checkd(seen, 39);
  end

  // Test: an NBA through a virtual interface writes a member of the instance the handle
  // designates when the statement runs, whether the handle is an argument, a local, a 'ref'
  // argument or a class property, with or without a timing control after it
  wire_if ifa ();
  wire_if ifb ();
  class Driver;
    virtual wire_if vif;
    task prop_nba(logic [3:0] x, bit wait_after);
      vif.n <= x;
      if (wait_after) #STEP;
    endtask
  endclass
  task automatic input_nba(virtual wire_if v, logic [3:0] x, bit wait_after);
    v.n <= x;
    if (wait_after) #STEP;
  endtask
  task automatic local_nba(logic [3:0] x, bit wait_after);
    virtual wire_if v;
    v = ifa;
    v.n <= x;
    if (wait_after) #STEP;
  endtask
  task automatic ref_nba(ref virtual wire_if v, input logic [3:0] x, input bit wait_after);
    v.n <= x;
    if (wait_after) #STEP;
  endtask
  // The handle rebound after the NBA: the NBA still writes the instance it designated
  task automatic rebind_nba(virtual wire_if v, logic [3:0] x);
    v.n <= x;
    v = ifb;
    #STEP;
  endtask
  initial begin
    automatic Driver d = new;
    automatic virtual wire_if h = ifa;
    #(STEP * 4);
    ifb.n = 4'd0;
    for (int w = 0; w < 2; ++w) begin
      input_nba(ifa, 4'd1 + 4'(w), w[0]);
      #STEP;
      `checkd(ifa.n, 4'd1 + 4'(w));
      local_nba(4'd3 + 4'(w), w[0]);
      #STEP;
      `checkd(ifa.n, 4'd3 + 4'(w));
      ref_nba(h, 4'd5 + 4'(w), w[0]);
      #STEP;
      `checkd(ifa.n, 4'd5 + 4'(w));
      d.vif = ifa;
      d.prop_nba(4'd7 + 4'(w), w[0]);
      #STEP;
      `checkd(ifa.n, 4'd7 + 4'(w));
    end
    rebind_nba(ifa, 4'd9);
    `checkd(ifa.n, 4'd9);
    `checkd(ifb.n, 4'd0);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
