// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define checks(gotv,expv) do if ((gotv) != (expv)) begin $write("%%Error: %s:%0d:  got='%s' exp='%s'\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// An interface declares a property with an untyped formal argument,
// instanced with actual arguments of two types, and is accessed through a
// virtual interface. Names seen by the user are the declared ones.
interface bus_if (
    input logic clk
);
  logic [7:0] data;
  logic [15:0] wide;
  string seen;

  property p_known(sig);
    (sig ^ sig) === '0;
  endproperty

  assert property (@(posedge clk) p_known(data));
  a_wide :
  assert property (@(posedge clk) p_known(wide)) seen = $sformatf("%m");
  c_wide :
  cover property (@(posedge clk) p_known(wide));

  function automatic logic [7:0] peek();
    return data;
  endfunction
endinterface

class reader;
  virtual bus_if vif;
  function logic [7:0] get();
    return vif.data;
  endfunction
  function logic [7:0] get_peek();
    return vif.peek();
  endfunction
endclass

module t;
  logic clk = 1'b0;
  bus_if bus (.clk(clk));
  reader r;

  always #5 clk = ~clk;

  initial begin
    r = new;
    r.vif = bus;
    bus.data = 8'h5a;
    bus.wide = 16'h1234;
    repeat (3) @(posedge clk);
    `checkh(r.get(), 8'h5a);
    `checkh(r.get_peek(), 8'h5a);
    `checks(bus.seen, "t.bus.a_wide");
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
