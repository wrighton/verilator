// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;
  bit clk;

  // Only a sequence or property instance takes an event expression
  function automatic bit f(bit x);
    return x;
  endfunction
  task automatic tk(bit x);
  endtask
  class Cls;
    function new(bit x);
    endfunction
    function void m(bit x);
    endfunction
  endclass
  Cls c;
  initial begin
    if (f(posedge clk)) $stop;
    tk(.x(negedge clk));
    c = new(edge clk);
    c.m(posedge clk);
  end

  // A typed formal not of type event takes no event expression
  property p_typed(bit ev);
    @(posedge clk) ev;
  endproperty
  assert property (p_typed(posedge clk));
  sequence s_typed(bit ev);
    ev;
  endsequence
  assert property (@(posedge clk) s_typed(posedge clk));
  assert property (@(posedge clk) s_typed(.ev(negedge clk)));
endmodule
