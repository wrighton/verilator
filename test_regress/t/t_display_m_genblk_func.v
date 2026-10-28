// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checks(gotv,expv) do if ((gotv) != (expv)) begin $write("%%Error: %s:%0d:  got='%s' exp='%s'\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// %m in a subroutine declared in a generate block names the subroutine once

module sub;
  if (1) begin : g
    function automatic string where();
      return $sformatf("%m");
    endfunction
  end
endmodule

module t;
  sub u ();

  if (1) begin : g
    function automatic string where();
      return $sformatf("%m");
    endfunction
    task automatic named(output string s);
      begin : blk
        s = $sformatf("%m");
      end
    endtask
    if (1) begin : h
      function automatic string where();
        return $sformatf("%m");
      endfunction
    end
  end

  for (genvar i = 0; i < 2; ++i) begin : gf
    function static string where();
      return $sformatf("%m");
    endfunction
  end

  function automatic string where();
    return $sformatf("%m");
  endfunction

  initial begin
    string s;
    `checks(g.where(), "t.g.where");
    g.named(s);
    `checks(s, "t.g.named.blk");
    `checks(g.h.where(), "t.g.h.where");
    `checks(gf[0].where(), "t.gf[0].where");
    `checks(gf[1].where(), "t.gf[1].where");
    `checks(u.g.where(), "t.u.g.where");
    `checks(where(), "t.where");
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
