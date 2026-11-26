// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define checks(gotv,expv) do if ((gotv) != (expv)) begin $write("%%Error: %s:%0d:  got='%s' exp='%s'\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Array method results used as a later item of an argument or item list
module t;
  initial begin
    begin
      bit [6:0] q[$];
      bit [6:0] d[];
      bit [6:0] f[2];
      q = '{100, 100};
      d = '{100, 100};
      f = '{100, 100};
      `checks($sformatf("%0d %0d", 0, q.sum()), "0 72");
      `checks($sformatf("%0d %p", 0, q.min()), "0 '{'h64}");
      `checks($sformatf("%0d %p", 0, q.unique_index()), "0 '{'h0}");
      `checks($sformatf("%0d %p", 0, q.find(x) with (x > 1)), "0 '{'h64, 'h64}");
      `checks($sformatf("%0d %p", 0, q.find_index(x) with (x > 1)), "0 '{'h0, 'h1}");
      `checks($sformatf("%0d %p", 0, q.map(x) with (x + 1)), "0 '{'h65, 'h65}");
      `checks($sformatf("%0d %0d", 0, d.sum()), "0 72");
      `checks($sformatf("%0d %0d", 0, f.sum() with (item)), "0 72");
      `checkh(7'd72 inside {7'd0, q.sum()}, 1'b1);
      case (7'd72)
        7'd0, q.sum(): ;
        default: `stop;
      endcase
    end
    begin
      bit [6:0] a[int];
      int k;
      a = '{1: 100, 2: 100};
      `checks($sformatf("%0d %b", 0, a.first(k)), "0 00000000000000000000000000000001");
      `checks($sformatf("%0d %0d", 0, a.sum()), "0 72");
      `checks($sformatf("%0d %p", 0, a.min()), "0 '{'h64}");
      `checks($sformatf("%0d %p", 0, a.unique_index()), "0 '{'h1}");
      `checks($sformatf("%0d %p", 0, a.find(x) with (x > 1)), "0 '{'h64, 'h64}");
      `checks($sformatf("%0d %p", 0, a.find_index(x) with (x > 1)), "0 '{'h1, 'h2}");
      `checks($sformatf("%0d %p", 0, a.map(x) with (x + 1)), "0 '{'h65, 'h65}");
    end
    begin
      bit [6:0] w[*];
      w = '{1: 100, 2: 100};
      `checks($sformatf("%0d %0d", 0, w.sum()), "0 72");
      `checks($sformatf("%0d %p", 0, w.min()), "0 '{'h64}");
      `checks($sformatf("%0d %p", 0, w.find(x) with (x > 1)), "0 '{'h64, 'h64}");
      `checks($sformatf("%0d %p", 0, w.map(x) with (x + 1)), "0 '{'h65, 'h65}");
    end
    begin
      bit [63:0] a[int];
      a = '{1: 64'h1_0000_0003, 2: 64'h5};
      `checks($sformatf("%0h %0h %0h", a.sum(), a.xor(), a.or()), "100000008 100000006 100000007");
    end
    // Negated membership matches the equivalent comparisons
    begin
      bit [6:0] q[$];
      bit [6:0] needle;
      bit hit;
      q = '{100, 100};
      `checkh(!(7'd72 inside {7'd0, q.sum()}), 1'b0);
      `checkh(!(7'd72 inside {q.sum(), 7'd0}), 1'b0);
      `checkh(!(7'd72 inside {7'd0, 7'd5, q.sum()}), 1'b0);
      `checkh(!(7'd73 inside {7'd0, q.sum()}), 1'b1);
      `checkh((7'd72 inside {7'd0, q.sum()}) != 1'b1, 1'b0);
      for (int n = 72; n <= 73; ++n) begin
        needle = 7'(n);
        `checkh(!(needle inside {7'd0, q.sum()}), !(needle == 7'd0 || needle == q.sum()));
        `checkh(!(needle inside {q.sum(), 7'd0}), !(needle == q.sum() || needle == 7'd0));
        `checkh(!(needle inside {7'd0, 7'd5, q.sum()}),
                needle != 7'd0 && needle != 7'd5 && needle != q.sum());
        case (needle) inside
          7'd0, q.sum(): hit = 1'b1;
          default: hit = 1'b0;
        endcase
        `checkh(hit, needle == q.sum());
      end
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
