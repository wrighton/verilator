// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Reduction methods on elements and 'with' results wider than 64 bits
module t;
  localparam bit [64:0] SUM = 65'h0_0000_0000_0000_0003;
  localparam bit [64:0] PRODUCT = 65'h1_ffff_ffff_ffff_fffd;
  localparam bit [64:0] AND = 65'h0_0000_0000_0000_0001;
  localparam bit [64:0] OR = 65'h1_ffff_ffff_ffff_ffff;
  localparam bit [64:0] XOR = 65'h1_ffff_ffff_ffff_fffd;

  initial begin
    begin
      bit [64:0] f[3];
      bit [64:0] d[];
      bit [64:0] q[$];
      bit [64:0] a[int];
      f = '{65'h0_ffff_ffff_ffff_ffff, 65'h0_0000_0000_0000_0003, 65'h1_0000_0000_0000_0001};
      d = f;
      q = f;
      a = '{1: f[0], 2: f[1], 3: f[2]};

      `checkh(d.sum(), SUM);
      `checkh(d.product(), PRODUCT);
      `checkh(d.and(), AND);
      `checkh(d.or(), OR);
      `checkh(d.xor(), XOR);
      `checkh(q.sum(), SUM);
      `checkh(q.product(), PRODUCT);
      `checkh(q.and(), AND);
      `checkh(q.or(), OR);
      `checkh(q.xor(), XOR);

      `checkh(d.sum() with (item), SUM);
      `checkh(d.product() with (item), PRODUCT);
      `checkh(d.and() with (item), AND);
      `checkh(d.or() with (item), OR);
      `checkh(d.xor() with (item), XOR);
      `checkh(f.sum() with (item), SUM);
      `checkh(f.product() with (item), PRODUCT);
      `checkh(f.and() with (item), AND);
      `checkh(f.or() with (item), OR);
      `checkh(f.xor() with (item), XOR);

      // Fixed-size, dynamic and associative arrays agree
      `checkh(d.sum(), f.sum());
      `checkh(d.product(), f.product());
      `checkh(d.and(), f.and());
      `checkh(d.or(), f.or());
      `checkh(d.xor(), f.xor());
      `checkh(a.sum(), f.sum());
      `checkh(a.product(), f.product());
      `checkh(a.and(), f.and());
      `checkh(a.or(), f.or());
      `checkh(a.xor(), f.xor());
    end
    begin
      int n[];
      int na[int];
      n = '{1, 2, 3};
      na = '{1: 1, 2: 2, 3: 3};
      `checkh(n.sum() with (65'(item) << 63), 65'h1_0000_0000_0000_0000);
      `checkh(na.sum() with (65'(item) << 63), 65'h1_0000_0000_0000_0000);
      `checkh(na.product() with (65'(item) << 1), 65'h30);
      `checkh(na.and() with (65'(item) | 65'h1_0000_0000_0000_0000), 65'h1_0000_0000_0000_0000);
      `checkh(na.or() with (65'(item) << 63), 65'h1_8000_0000_0000_0000);
      `checkh(na.xor() with (65'(item) << 63), 65'h0);
    end
    begin
      bit [64:0] e[];
      int ea[int];
      `checkh(e.sum(), 65'h0);
      `checkh(e.product(), 65'h0);
      `checkh(e.and(), 65'h0);
      `checkh(e.product() with (item), 65'h0);
      `checkh(e.and() with (item), 65'h0);
      `checkh(ea.product() with (65'(item)), 65'h0);
      `checkh(ea.and() with (65'(item)), 65'h0);
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
