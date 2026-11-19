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

// The port itself as the scope through a modport port (pins the modport branch with the port
// as the last component)
module subm2 (
    ifc.mp p
);
  initial $assertoff(0, p);
endmodule

// The port itself as the scope from some instances only, in both orders (pins the mixed-instance
// branch taking the connected instance as the target)
module leafp;
  initial $assertoff(0, holder.p);
endmodule
module hportp (
    ifc p
);
  leafp l ();
endmodule
module hgenp (
    input logic clk
);
  if (1) begin : p
    a1 :
    assert property (@(posedge clk) 0);
  end
  leafp l ();
endmodule
module ua3 (
    input logic clk
);
  ifc i0 (.clk(clk));
  hportp holder (.p(i0));
endmodule
module ub3 (
    input logic clk
);
  hgenp holder (.clk(clk));
endmodule
module leafp2;
  initial $assertoff(0, holder.p);
endmodule
module hportp2 (
    ifc p
);
  leafp2 l ();
endmodule
module hgenp2 (
    input logic clk
);
  if (1) begin : p
    a1 :
    assert property (@(posedge clk) 0);
  end
  leafp2 l ();
endmodule
module ua4 (
    input logic clk
);
  ifc i0 (.clk(clk));
  hportp2 holder (.p(i0));
endmodule
module ub4 (
    input logic clk
);
  hgenp2 holder (.clk(clk));
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
  subm2 sm2 (.p(v0));
  ua3 a3 (.clk(clk));
  ub3 b3 (.clk(clk));
  ub4 b4 (.clk(clk));
  ua4 a4 (.clk(clk));
  // A virtual interface variable can name different instances during simulation (IEEE 1800-2023
  // 25.9)
  initial begin
    $assertoff(0, vif.a1);
    $assertoff(0, c.vif.a1);
    $assertoff(0, vifs[0].a1);
  end
endmodule
