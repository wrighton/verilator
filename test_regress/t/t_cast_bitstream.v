// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Bit-stream casts to and from fixed-size unpacked types (IEEE 1800-2023 6.24.3)

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module sub #(
    parameter type DATA_T = logic
) (
    input clk,
    input logic [2*$bits(DATA_T)-1:0] rd,
    input logic byp,
    input DATA_T src,
    output DATA_T out1,
    output DATA_T out0,
    output DATA_T outb
);
  typedef DATA_T pp_array_t[1:0];
  pp_array_t pp_q;
  always @(posedge clk) begin
    pp_q <= pp_array_t'(rd);
    outb <= byp ? src : DATA_T'(rd[$bits(DATA_T)-1:0]);
  end
  assign out1 = pp_q[1];
  assign out0 = pp_q[0];
endmodule

module t (
    input clk
);

  typedef logic [7:0] v8_t;
  typedef logic [14:0] v15_t;
  typedef logic signed [14:0] s15_t;
  typedef logic [20:0] v21_t;
  typedef logic [21:0] v22_t;
  typedef logic [29:0] v30_t;
  typedef logic [98:0] v99_t;
  typedef logic [3:0] pair_t[1:0];
  typedef logic [6:0] asc_t[0:2];
  typedef logic [32:0] wide_t[3:1];
  typedef logic [1:0] grid_t[2:1][0:1];
  typedef logic [1:0] quad_t[4];
  typedef struct {
    logic [7:0] a;
    logic [6:0] b;
  } us_t;
  typedef struct packed {
    logic [7:0] a;
    logic [6:0] b;
  } ps_t;
  typedef us_t us_pair_t[2:1];
  typedef ps_t ps_pair_t[1:0];
  typedef struct {
    logic [2:0] c;
    us_t s;
    logic [1:0] arr[2];
  } nest_t;

  logic [98:0] crc = 99'h5_5aef0c8d_d70a4497_3fa1b2c3;

  function automatic us_t ident(us_t s);
    return s;
  endfunction

  initial begin
    for (int i = 0; i < 20; ++i) begin
      crc = {crc[97:0], crc[98] ^ crc[63] ^ crc[2]};
      begin
        // Packed to unpacked array, and back
        pair_t a;
        asc_t asc;
        wide_t w;
        grid_t g;
        a = pair_t'(crc[7:0]);
        `checkh(a[1], crc[7:4]);
        `checkh(a[0], crc[3:0]);
        `checkh(v8_t'(a), crc[7:0]);
        asc = asc_t'(crc[20:0]);
        `checkh(asc[0], crc[20:14]);
        `checkh(asc[2], crc[6:0]);
        `checkh(v21_t'(asc), crc[20:0]);
        w = wide_t'(crc);
        `checkh(w[3], crc[98:66]);
        `checkh(w[1], crc[32:0]);
        `checkh(v99_t'(w), crc);
        g = grid_t'(crc[7:0]);
        `checkh(g[2][0], crc[7:6]);
        `checkh(g[1][1], crc[1:0]);
        `checkh(v8_t'(g), crc[7:0]);
      end
      begin
        // Packed to unpacked struct, and back
        us_t s;
        ps_t p;
        int n;
        s = us_t'(crc[14:0]);
        `checkh(s.a, crc[14:7]);
        `checkh(s.b, crc[6:0]);
        `checkh(v15_t'(s), crc[14:0]);
        p = ps_t'(s);
        `checkh(p, crc[14:0]);
        s = us_t'(p);
        `checkh(s.b, crc[6:0]);
        n = int'(s15_t'(s));
        `checkh(n, {{17{crc[14]}}, crc[14:0]});
        s = us_t'(s);
        `checkh(s.a, crc[14:7]);
        s = us_t'(ident(s));
        `checkh(s.a, crc[14:7]);
      end
      begin
        // Arrays of structs
        us_pair_t up;
        ps_pair_t pp;
        up = us_pair_t'(crc[29:0]);
        `checkh(up[2].a, crc[29:22]);
        `checkh(up[2].b, crc[21:15]);
        `checkh(up[1].a, crc[14:7]);
        `checkh(v30_t'(up), crc[29:0]);
        pp = ps_pair_t'(crc[29:0]);
        `checkh(pp[1], crc[29:15]);
        `checkh(pp[0], crc[14:0]);
        `checkh(v30_t'(pp), crc[29:0]);
      end
      begin
        // Unpacked to unpacked of another shape
        pair_t a;
        quad_t q;
        nest_t n;
        us_t s;
        a = pair_t'(crc[7:0]);
        q = quad_t'(a);
        `checkh(q[0], crc[7:6]);
        `checkh(q[3], crc[1:0]);
        n = nest_t'(crc[21:0]);
        `checkh(n.c, crc[21:19]);
        `checkh(n.s.b, crc[10:4]);
        `checkh(n.arr[0], crc[3:2]);
        `checkh(n.arr[1], crc[1:0]);
        `checkh(v22_t'(n), crc[21:0]);
        s = us_t'(n.s);
        `checkh(s.b, crc[10:4]);
      end
      begin
        // To the same type, not a bit-stream type
        typedef struct {
          real r;
          string s;
        } rs_t;
        typedef union {logic [7:0] a;} uu_t;
        rs_t rs1, rs2;
        uu_t uu1, uu2;
        rs2.r = real'(crc[7:0]);
        rs2.s = "x";
        rs1 = rs_t'(rs2);
        `checkh(rs1.r, real'(crc[7:0]));
        uu2.a = crc[7:0];
        uu1 = uu_t'(uu2);
        `checkh(uu1.a, crc[7:0]);
      end
      begin
        // Not directly assigned
        us_t s;
        pair_t a;
        grid_t g;
        s = crc[0] ? us_t'(crc[14:0]) : us_t'(crc[29:15]);
        `checkh(s.a, crc[0] ? crc[14:7] : crc[29:22]);
        a = crc[1] ? pair_t'(crc[7:0]) : pair_t'(crc[15:8]);
        `checkh(a[1], crc[1] ? crc[7:4] : crc[15:12]);
        g = crc[2] ? grid_t'(crc[7:0]) : grid_t'(crc[15:8]);
        `checkh(g[2][0], crc[2] ? crc[7:6] : crc[15:14]);
        `checkh(g[1][1], crc[2] ? crc[1:0] : crc[9:8]);
      end
    end
  end

  // In a parameterized module, as nonblocking assignments
  int cyc = 0;
  logic [29:0] rd;
  us_t src = '{8'h12, 7'h34};
  us_t us1, us0, usb;
  ps_t ps1, ps0, psb;
  sub #(.DATA_T(us_t)) u_us (.clk, .rd, .byp(rd[0]), .src, .out1(us1), .out0(us0), .outb(usb));
  sub #(.DATA_T(ps_t)) u_ps (.clk, .rd, .byp(rd[0]), .src(ps_t'(src)), .out1(ps1), .out0(ps0),
                             .outb(psb));
  always @(posedge clk) begin
    cyc <= cyc + 1;
    rd <= crc[29:0] + 30'(cyc * 32'h1234567);
    if (cyc > 1) begin
      `checkh(us1.a, $past(rd[29:22]));
      `checkh(us0.b, $past(rd[6:0]));
      `checkh(usb.a, $past(rd[0]) ? 8'h12 : $past(rd[14:7]));
      `checkh(ps1, $past(rd[29:15]));
      `checkh(ps0, $past(rd[14:0]));
      `checkh(psb, $past(rd[0]) ? 15'h0934 : $past(rd[14:0]));
    end
    if (cyc == 20) begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end

endmodule
