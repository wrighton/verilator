// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// A 'unique' constraint over associative arrays holds over the entries they
// have when randomize() is called, including entries added after new().

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0)
// verilog_format: on

typedef bit [2:0] val_t;

class C;
  rand val_t aa[int];
  rand val_t bb[string];
  constraint u_one {unique {aa};}
  constraint u_two {unique {aa, bb};}
endclass

module t;
  initial begin
    automatic C c = new;
    val_t vals[$];
    int ok;

    c.aa[-2] = 0;
    c.aa[5] = 0;
    c.aa[9] = 0;
    c.bb["x"] = 0;
    c.bb["y"] = 0;
    for (int n = 0; n < 10; ++n) begin
      ok = c.randomize();
      `checkd(ok, 1);
      `checkd(c.aa.size(), 3);
      `checkd(c.bb.size(), 2);
      vals = '{};
      foreach (c.aa[k]) vals.push_back(c.aa[k]);
      foreach (c.bb[k]) vals.push_back(c.bb[k]);
      foreach (vals[i])
      foreach (vals[j])
      if (i < j && vals[i] == vals[j]) begin
        $write("%%Error: %s:%0d: members %0d and %0d both hold %0d\n", `__FILE__, `__LINE__, i, j,
               vals[i]);
        `stop;
      end
    end

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
