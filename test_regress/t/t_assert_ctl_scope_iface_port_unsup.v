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

// The port itself as the scope through a modport port (pins the modport branch with the port
// as the last component)
module subm2 (
    ifc.mp p
);
  initial $assertoff(0, p);
endmodule

module t;
  logic clk = 0;
  ifc v0 (.clk(clk));
  ifc v1 (.clk(clk));
  virtual ifc vif = v0;
  virtual ifc vifs[2];
  child c (.p(v1));
  subm sm (.p(v0));
  subm2 sm2 (.p(v0));
  // A virtual interface variable can name different instances during simulation (IEEE 1800-2023
  // 25.9)
  initial begin
    $assertoff(0, vif.a1);
    $assertoff(0, c.vif.a1);
    $assertoff(0, vifs[0].a1);
  end
endmodule
