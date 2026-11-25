// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// A class member written by an overriding virtual method called by a clocked process is seen
// after a #0 in the same time step

module t (
    input bit clk,
    output int x
);
  class payload;
    int value;
    virtual function void set_value();
    endfunction
  endclass
  class derived extends payload;
    virtual function void set_value();
      value = 17;
    endfunction
  endclass
  derived obj = new;
  payload p = obj;
  payload alias_p = p;
  always @(posedge clk) p.set_value();
  always @(posedge clk) begin
    #0 x = alias_p.value;
  end
endmodule
