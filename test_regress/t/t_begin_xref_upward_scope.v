// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Block-relative hierarchical names resolve upwards in the nearest enclosing
// scope that has the named block (IEEE 1800-2023 23.8), not the module's block
// of the same name

interface ifc;
  logic val;
endinterface

module t;
  localparam realtime STEP = 1;
  int r_in, r_deep, r_sib, r_mod;

  // The same for generate blocks, with an interface instance
  ifc i0 ();
  if (1) begin : gb
    ifc i0 ();
    if (1) begin : gi
      assign i0.val = 1'b1;  // gb.i0, the enclosing block's
    end
  end
  assign i0.val = 1'b0;

  initial begin : mid2
    int w;
    w = 111;
  end

  initial begin
    #(STEP);
    begin : vb
      begin : mid2
        int w;
        w = 3;
        begin : inner
          r_in = mid2.w;  // vb.mid2, the enclosing block
        end
      end
    end
    begin : a
      begin : mid2
        int w;
        w = 4;
        begin : b
          begin : c
            r_deep = mid2.w;  // a.mid2, three levels up
          end
        end
      end
    end
    begin : s
      begin : mid2
        int w;
        w = 5;
      end
      begin : s2
        r_sib = mid2.w;  // s.mid2, a sibling's
      end
    end
    begin : vc
      r_mod = mid2.w;  // No enclosing block has a mid2: the module's
    end
    `checkd(r_in, 3);
    `checkd(r_deep, 4);
    `checkd(r_sib, 5);
    `checkd(r_mod, 111);
    `checkd(gb.i0.val, 1'b1);
    `checkd(i0.val, 1'b0);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
