// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkp(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%p exp=%p\n", `__FILE__, `__LINE__, (gotv), (expv)); `stop; end while(0);
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__, `__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Static cast between assignment compatible unpacked array kinds (IEEE 1800-2023 6.24.1, 7.6)
module t;

  typedef bit [6:0] q_t[$];
  typedef bit [6:0] d_t[];

  initial begin
    begin
      bit [6:0] d[];
      q_t q;
      d = new[2];
      d[0] = 7'h11;
      d[1] = 7'h22;
      q = q_t'(d);
      `checkd(q.size(), 2);
      `checkd(q[1], 7'h22);
      `checkd(q_t'(d) == q, 1'b1);
      q.push_back(7'h33);
      `checkd(q_t'(d) != q, 1'b1);
    end
    begin
      bit [6:0] q[$];
      d_t d;
      d_t exp;
      exp = '{7'h1, 7'h2, 7'h3};
      q = '{7'h1, 7'h2, 7'h3};
      d = d_t'(q);
      `checkp(d, exp);
      `checkd(d_t'(q) == d, 1'b1);
    end
    begin
      bit [6:0] f[1:3];
      bit [6:0] g[0:2];
      q_t q;
      d_t d;
      q_t expf;
      d_t expg;
      expf = '{7'h4, 7'h5, 7'h6};
      expg = '{7'h7, 7'h8, 7'h9};
      f = '{7'h4, 7'h5, 7'h6};
      g = '{7'h7, 7'h8, 7'h9};
      q = q_t'(f);
      `checkp(q, expf);
      d = d_t'(g);
      `checkp(d, expg);
      `checkd(d_t'(g) == expg, 1'b1);
      `checkd(q_t'(f) == expf, 1'b1);
      `checkd(q_t'(f) != q_t'(g), 1'b1);
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end

endmodule
