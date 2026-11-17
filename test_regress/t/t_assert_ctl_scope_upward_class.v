// DESCRIPTION: Verilator: Selective assertion control by an upward name from a class in a module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

`timescale 1ns / 1ps

module leaf;
  int failures = 0;
  initial begin
    #1;
    check :
    assert (1'b0)
    else failures++;
  end
endmodule

module par (
    input bit off,
    input bit off2
);
  leaf sib ();
  leaf sib2 ();
  // A name in a class method resolves from where the class is declared, so from this
  // instance of the module declaring it (IEEE 1800-2023 8.23, 23.8)
  class C;
    function void off_sib();
      $assertoff(0, sib);
    endfunction
  endclass
  initial begin
    if (off) begin
      automatic C c = new;
      c.off_sib();
    end
  end
  // Also from a class in a generate block
  if (1) begin : gc
    class G;
      function void off_sib2();
        $assertoff(0, sib2);
      endfunction
    endclass
    initial begin
      if (off2) begin
        automatic G g = new;
        g.off_sib2();
      end
    end
  end
endmodule

module t;
  int top_failures = 0;
  par p0 (
      .off(1'b1),
      .off2(1'b0)
  );
  par p1 (
      .off(1'b0),
      .off2(1'b1)
  );
  initial begin
    #1;
    top_check :
    assert (1'b0)
    else top_failures++;
    #1;
    `checkd(p0.sib.failures, 0);
    `checkd(p1.sib.failures, 1);
    `checkd(p0.sib2.failures, 1);
    `checkd(p1.sib2.failures, 0);
    `checkd(top_failures, 1);
    $display("*-* All Finished *-*");
    $finish;
  end
endmodule
