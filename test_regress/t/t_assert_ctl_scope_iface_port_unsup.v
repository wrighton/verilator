// DESCRIPTION: Verilator: Unsupported assertion control scopes through virtual interfaces and modports
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

interface ifc (
    input logic clk
);
  int n = 0;
  a1 :
  assert property (@(posedge clk) 0)
  else n++;
  task automatic tsk(input bit v);
    a2 :
    assert (v)
    else n++;
  endtask
  modport mp(import tsk);
endinterface

module child (
    ifc p
);
  virtual ifc vif = p;
endmodule

// The task is listed in the modport, but the assertion control state of its assertion is not
module subm (
    ifc.mp p
);
  initial $assertoff(0, p.tsk);
endmodule

// One upward name crosses a port from some instances only, in both orders
module leafm;
  initial $assertoff(0, holder.p.a1);
endmodule
module hport (
    ifc p
);
  leafm l ();
endmodule
module hgen (
    input logic clk
);
  if (1) begin : p
    int n = 0;
    a1 :
    assert property (@(posedge clk) 0)
    else n++;
  end
  leafm l ();
endmodule
module ua (
    input logic clk
);
  ifc i0 (.clk(clk));
  hport holder (.p(i0));
endmodule
module ub (
    input logic clk
);
  hgen holder (.clk(clk));
endmodule
module leafm2;
  initial $assertoff(0, holder.p.a1);
endmodule
module hport2 (
    ifc p
);
  leafm2 l ();
endmodule
module hgen2 (
    input logic clk
);
  if (1) begin : p
    int n = 0;
    a1 :
    assert property (@(posedge clk) 0)
    else n++;
  end
  leafm2 l ();
endmodule
module ua2 (
    input logic clk
);
  ifc i0 (.clk(clk));
  hport2 holder (.p(i0));
endmodule
module ub2 (
    input logic clk
);
  hgen2 holder (.clk(clk));
endmodule

module t;
  logic clk = 0;
  ifc v0 (.clk(clk));
  ifc v1 (.clk(clk));
  virtual ifc vif = v0;
  virtual ifc vifs[2];
  ua a (.clk(clk));
  ub b (.clk(clk));
  ub2 b2 (.clk(clk));
  ua2 a2 (.clk(clk));
  child c (.p(v1));
  subm sm (.p(v0));
  // A virtual interface variable can name different instances during simulation (IEEE 1800-2023
  // 25.9)
  initial begin
    $assertoff(0, vif.a1);
    $assertoff(0, c.vif.a1);
    $assertoff(0, vifs[0].a1);
  end
endmodule
