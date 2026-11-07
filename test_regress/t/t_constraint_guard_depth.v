// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Branch formatting must grow linearly with nested mixed-state/random guards.
class DeepGuard;
  bit [11:0] g;
  rand bit [11:0] r;
  rand bit [6:0] value;
  constraint c {
    if (g[0] || r[0]) {
      if (g[1] || r[1]) {
        if (g[2] || r[2]) {
          if (g[3] || r[3]) {
            if (g[4] || r[4]) {
              if (g[5] || r[5]) {
                if (g[6] || r[6]) {
                  if (g[7] || r[7]) {
                    if (g[8] || r[8]) {
                      if (g[9] || r[9]) {
                        if (g[10] || r[10]) {if (g[11] || r[11]) {value == 7'd23;}}
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
endclass

module t;
  initial begin
    automatic DeepGuard d = new;
    int res;
    for (int i = 0; i < 10; ++i) begin
      d.g = '1;
      res = d.randomize();
      `checkd(res, 1);
      `checkd(d.value, 7'd23);
      d.g = '0;
      res = d.randomize() with {r == 12'hfff;};
      `checkd(res, 1);
      `checkd(d.value, 7'd23);
      res = d.randomize() with {
        r == 0;
        value == 7'd9;
      };
      `checkd(res, 1);
      `checkd(d.value, 7'd9);
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
