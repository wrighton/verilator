// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkr(gotv,expv) do if ((gotv) != (expv)) begin $write("%%Error: %s:%0d:  got=%f exp=%f\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module t;
  localparam real NAN = $bitstoreal(64'h7ff8_0000_0000_0000);

  // A covergroup sampled on a change of a real, which -0.0 after 0.0 is, and keeping a NaN is
  // not, so steps 1 and 2 are sampled, but not 3 and 4
  class Cls;
    real m_r = 0.0;
    int m_step = 0;
    covergroup cg @(m_r);
      coverpoint m_step {bins b[] = {[1:4]};}
    endgroup
    function new;
      cg = new;
    endfunction
    function void step(int n, real r);
      m_step = n;
      m_r = r;
    endfunction
  endclass

  initial begin
    automatic Cls c = new;
    #1 c.step(1, -0.0);
    #1 c.step(2, NAN);
    #1 c.step(3, NAN);
    #1 c.step(4, NAN);
    #1;
    `checkr(c.cg.get_inst_coverage(), 50.0);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
