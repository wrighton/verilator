// DESCRIPTION: Verilator: DPI scopes that exist only for a %m
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

import "DPI-C" context function void dpic_scopes();
import "DPI-C" context function void dpic_context();

interface ifc;
  function automatic string name();
    return $sformatf("%m");
  endfunction
endinterface

module leaf (ifc port);
  task automatic run;
    $display("run %m");
    begin : named
      $display("named %m %s", port.name());
    end
  endtask
endmodule

module ctx;
  // Both a %m and a DPI context scope
  task automatic run;
    $display("ctx %m");
    dpic_context();
  endtask
endmodule

module t;
  ifc i1 ();
  ifc i2 ();
  leaf u1 (i1);
  leaf u2 (i2);
  ctx u_ctx ();
  initial begin
    u1.run();
    u2.run();
    u_ctx.run();
    dpic_scopes();
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
