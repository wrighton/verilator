// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define checkrd(gotv,v,vw,pos,w) `checkh(65'(gotv), rd(65'(v), vw, pos, w))
// verilog_format: on

// verilator lint_off ASCRANGE
// verilator lint_off SELRANGE
// verilator lint_off WIDTH

// Bits [pos +: w] of the vw-bit value v, where a bit out of range reads zero
// (IEEE 1800-2023 11.5.1). Only positions in range are selected.
function automatic bit [64:0] rd(bit [64:0] v, int vw, longint pos, int w);
  rd = '0;
  for (longint k = 0; k < w; ++k) begin
    if (pos + k >= 0 && pos + k < vw) rd[k] = v[pos+k];
  end
endfunction

class Unique;
  rand bit [7:0] x;
  rand bit [2:0] i;
  constraint c {
    x == 8'b0000_0100;
    x[i] == 1'b1;
  }
endclass

class RandIndex;
  rand bit [7:0] a;
  rand bit [0:7] b;
  rand bit [15:8] c;
  rand bit [64:0] w;
  rand bit [3:0] i;
  rand bit [4:0] j;
  rand bit signed [3:0] s;
  rand bit [39:0] l;
  rand bit [69:0] h;
  rand bit [6:0] k;
  rand bit ab, bb, cb, sb, lb, hb, wb;
  rand bit [3:0] ap, am, bp, cm, sp;
  constraint c_sel {
    ab == a[i];
    bb == b[i];
    cb == c[j];
    sb == a[s];
    lb == a[l];
    hb == a[h];
    wb == w[k];
    ap == a[i+:4];
    am == a[i-:4];
    bp == b[i+:4];
    cm == c[j-:4];
    sp == a[s+:4];
  }
  constraint c_wide {
    l < 16 || l[39:32] == 8'h01;
    h < 16 || h[69];
  }
endclass

class StateIndex;
  rand bit [7:0] x;
  rand bit [0:7] b;
  int i;
  rand bit y;
  rand bit [3:0] yp, ym, bp;
  constraint c {
    x == 8'hff;
    b == 8'hff;
    y == x[i];
    yp == x[i+:4];
    ym == x[i-:4];
    bp == b[i+:4];
  }
endclass

class ConstIndex;
  rand bit [7:0] x;
  rand bit [5:0] x6;
  rand bit y, y6;
  rand bit [3:0] yp, yq, yn, ym, y64;
  constraint c {
    x == 8'hff;
    x6 == 6'h3f;
    y6 == x6[6];
    y64 == x6[7:4];
    y == x[20];
    yp == x[6+:4];
    yq == x[10+:4];
    yn == x[-2+:4];
    ym == x[-1-:4];
  }
endclass

class CondIndex;
  rand bit [7:0] x;
  int i;
  rand bit y;
  constraint c {
    x == 8'hff;
    if (x[i]) y == 1'b1;
    else y == 1'b0;
  }
endclass

class NearMax;
  rand bit [7:0] x;
  rand bit [15:8] c;
  rand bit [31:0] u;
  rand bit [32:0] v;
  rand bit [63:0] w;
  rand bit signed [39:0] sw;
  bit [31:0] su;
  rand bit [2:0] yu, yv, yw, yc, ys, yk3, ysw, ykn;
  rand bit yk;
  constraint c_near {
    u inside {32'hffff_ffff, 32'hffff_fffe, 32'h8000_0000, 32'h7fff_ffff};
    v inside {33'h0_ffff_ffff, 33'h1_0000_0001, 33'h1_ffff_ffff};
    w inside {64'hffff_ffff_ffff_ffff, 64'hffff_ffff_ffff_fffe, 64'h8000_0000_0000_0001};
    sw inside {-40'sd1, -40'sd2, 40'sh7f_ffff_ffff, 40'sh80_0000_0000};
    yu == x[u+:3];
    yv == x[v+:3];
    yw == x[w-:3];
    yc == c[u+:3];
    ys == x[su+:3];
    yk == x[33'h1_0000_0001];
    yk3 == x[64'hffff_ffff_ffff_fffe+:3];
    ysw == x[sw+:3];
    ykn == x[64'sh8000_0000_0000_0000+:3];
  }
endclass

class PackedIndex;
  rand bit [3:0][6:0] pa;
  rand bit [5:2][6:0] po;
  rand bit [39:0] l;
  rand bit [2:0] i;
  rand bit [6:0] yl, yo;
  constraint c {
    l < 6 || l[39:32] == 8'h01;
    yl == pa[l];
    yo == po[i];
  }
endclass

function automatic bit [2:0] pick3(bit [7:0] v, bit [2:0] k);
  return v[k+:3];
endfunction

class Forms;
  rand bit [7:0] x;
  rand bit [0:7] b;
  rand int v;
  rand bit [2:0] k;
  rand bit [4:0] q;
  rand bit [2:0] yf;
  rand bit yb, yv;
  constraint c {
    yf == pick3(x, k);
    yb == b[3];
    yv == v[q];
  }
endclass

// verilator lint_on WIDTH
class NegRange;
  rand bit [-6:0] an;
  rand bit [0:-6] ad;
  rand bit [-3:4] az;
  rand bit [7:-2] aw;
  rand int idx;
  rand bit yn, yd;
  rand bit [2:0] ynp, ydp, yzm, ywm;
  constraint c {
    idx inside {[-10 : 10]};
    yn == an[idx];
    ynp == an[idx+:3];
    yd == ad[idx];
    ydp == ad[idx+:3];
    yzm == az[idx-:3];
    ywm == aw[idx-:3];
  }
endclass
// verilator lint_off WIDTH

class NearMaxForce;
  rand bit [7:0] x;
  rand bit [32:0] v;
  constraint c {
    x == 8'hff;
    v == 33'h0_ffff_ffff;
    x[v+:3] == 3'b010;
  }
endclass

class Solved;
  rand bit [7:0] x;
  int i;
  constraint c {x[i+:4] == 4'b0011;}
endclass

class Over;
  rand bit [7:0] x;
  rand bit [3:0] i;
  rand bit y;
  constraint c {
    i >= 8;
    y == x[i];
    y == 1'b1;
  }
endclass

class Unsat;
  rand bit [7:0] x;
  rand int i;
  constraint c {
    x == 8'hff;
    i == 6;
    x[i+:4] == 4'b1111;
  }
endclass

class Plain;
  rand bit [7:0] x;
  rand bit y;
endclass

class Modes;
  rand bit [7:0] x;
  rand int i;
  rand bit y;
  constraint c {y == x[i];}
endclass

module t;
  int randomize_result;

  initial begin
    // Test: the only position that satisfies the constraint is found
    begin
      automatic Unique o = new;
      repeat (8) begin
        randomize_result = o.randomize();
        `checkd(randomize_result, 1);
        `checkh(o.i, 3'd2);
      end
    end

    // Test: random positions, in and out of range, read as the select does
    begin
      automatic RandIndex o = new;
      automatic int outOfRange = 0;
      repeat (40) begin
        randomize_result = o.randomize();
        `checkd(randomize_result, 1);
        if (o.i > 7) ++outOfRange;
        `checkrd(o.ab, o.a, 8, o.i, 1);
        `checkrd(o.bb, o.b, 8, 7 - longint'(o.i), 1);
        `checkrd(o.cb, o.c, 8, longint'(o.j) - 8, 1);
        `checkrd(o.sb, o.a, 8, o.s, 1);
        `checkrd(o.lb, o.a, 8, o.l, 1);
        `checkh(o.hb, o.h < 8 ? o.a[o.h[2:0]] : 1'b0);
        `checkrd(o.wb, o.w, 65, o.k, 1);
        `checkrd(o.ap, o.a, 8, o.i, 4);
        `checkrd(o.am, o.a, 8, longint'(o.i) - 3, 4);
        // b[i+:4] is b[i:i+3], so its least significant bit is b[i+3]
        `checkrd(o.bp, o.b, 8, 4 - longint'(o.i), 4);
        `checkrd(o.cm, o.c, 8, longint'(o.j) - 11, 4);
        `checkrd(o.sp, o.a, 8, o.s, 4);
      end
      if (outOfRange == 0 || outOfRange == 40) `stop;
    end

    // Test: state positions, including negative ones, read zero out of range
    begin
      automatic StateIndex o = new;
      automatic int positions[$] = '{-12, -5, -2, -1, 0, 1, 3, 6, 7, 8, 10, 11, 20, 32'h7fffffff};
      foreach (positions[n]) begin
        o.i = positions[n];
        randomize_result = o.randomize();
        `checkd(randomize_result, 1);
        `checkrd(o.y, o.x, 8, o.i, 1);
        `checkrd(o.yp, o.x, 8, o.i, 4);
        `checkrd(o.ym, o.x, 8, longint'(o.i) - 3, 4);
        `checkrd(o.bp, o.b, 8, 4 - longint'(o.i), 4);
      end
    end

    // Test: constant positions out of range
    begin
      automatic ConstIndex o = new;
      randomize_result = o.randomize();
      `checkd(randomize_result, 1);
      `checkh(o.y6, 1'b0);
      `checkh(o.y64, 4'b0011);
      `checkh(o.y, 1'b0);
      `checkh(o.yp, 4'b0011);
      `checkh(o.yq, 4'b0000);
      `checkh(o.yn, 4'b1100);
      `checkh(o.ym, 4'b0000);
    end

    // Test: a condition reads zero out of range
    begin
      automatic CondIndex o = new;
      o.i = 19;
      randomize_result = o.randomize();
      `checkd(randomize_result, 1);
      `checkh(o.y, 1'b0);
      o.i = 3;
      randomize_result = o.randomize();
      `checkd(randomize_result, 1);
      `checkh(o.y, 1'b1);
    end

    // Test: positions near the maximum. An index of up to 32 bits is an integer, so an unsigned
    // one with its top bit set is negative, as major simulators read it (strict IEEE unsigned
    // would put 32'hffff_ffff out of range). A wider index keeps its whole value.
    begin
      automatic NearMax o = new;
      automatic NearMaxForce force_o = new;
      o.su = 32'hffff_ffff;
      repeat (20) begin
        randomize_result = o.randomize();
        `checkd(randomize_result, 1);
        `checkrd(o.yu, o.x, 8, int'(o.u), 3);
        `checkh(o.yv, 3'b0);
        `checkh(o.yw, 3'b0);
        `checkrd(o.yc, o.c, 8, int'(o.u) - 8, 3);
        `checkrd(o.ys, o.x, 8, -1, 3);
        `checkh(o.yk, 1'b0);
        `checkh(o.yk3, 3'b0);
        `checkrd(o.ysw, o.x, 8, o.sw, 3);
        `checkh(o.ykn, 3'b0);
      end
      randomize_result = force_o.randomize();
      `checkd(randomize_result, 0);
    end

    // Test: a select in a called function, an ascending constant select, and an int select
    begin
      automatic Forms o = new;
      repeat (20) begin
        randomize_result = o.randomize();
        `checkd(randomize_result, 1);
        `checkrd(o.yf, o.x, 8, o.k, 3);
        `checkh(o.yb, o.b[3]);
        `checkh(o.yv, o.v[o.q]);
      end
    end

    // Test: negative and zero-spanning declared ranges, ascending and descending
    begin
      automatic NegRange o = new;
      repeat (40) begin
        randomize_result = o.randomize();
        `checkd(randomize_result, 1);
        `checkrd(o.yn, o.an, 7, -o.idx, 1);
        `checkrd(o.ynp, o.an, 7, -o.idx - 2, 3);
        `checkrd(o.yd, o.ad, 7, o.idx + 6, 1);
        `checkrd(o.ydp, o.ad, 7, o.idx + 6, 3);
        `checkrd(o.yzm, o.az, 8, 4 - o.idx, 3);
        `checkrd(o.ywm, o.aw, 10, o.idx, 3);
      end
    end

    // Test: packed array elements out of range read zero
    begin
      automatic PackedIndex o = new;
      repeat (20) begin
        randomize_result = o.randomize();
        `checkd(randomize_result, 1);
        `checkh(o.yl, o.l < 4 ? o.pa[o.l[1:0]] : 7'h0);
        `checkh(o.yo, o.i >= 2 && o.i <= 5 ? o.po[o.i] : 7'h0);
      end
    end

    // Test: the selected value is solved, and bits out of range stay zero
    begin
      automatic Solved o = new;
      o.i = 6;
      repeat (4) begin
        randomize_result = o.randomize();
        `checkd(randomize_result, 1);
        `checkh(o.x[7:6], 2'b11);
      end
      o.i = 10;
      randomize_result = o.randomize();
      `checkd(randomize_result, 0);
    end

    // Test: over-constrained and unsatisfiable selects fail
    begin
      automatic Over over = new;
      automatic Unsat unsat = new;
      automatic Plain plain = new;
      randomize_result = over.randomize();
      `checkd(randomize_result, 0);
      randomize_result = unsat.randomize();
      `checkd(randomize_result, 0);
      // An unrelated randomization still succeeds afterwards
      randomize_result = plain.randomize() with {x == 8'h5a;};
      `checkd(randomize_result, 1);
      `checkh(plain.x, 8'h5a);
    end

    // Test: inline constraints read zero out of range
    begin
      automatic Plain o = new;
      automatic int i = 20;
      automatic bit [7:0] lx;
      automatic bit ly;
      randomize_result = o.randomize() with {x == 8'hff; y == x[i];};
      `checkd(randomize_result, 1);
      `checkh(o.y, 1'b0);
      randomize_result = std::randomize(lx, ly) with {lx == 8'hff; ly == lx[i];};
      `checkd(randomize_result, 1);
      `checkh(ly, 1'b0);
    end

    // Test: a select of state only reads zero out of range
    begin
      automatic Modes o = new;
      o.x = 8'hff;
      o.i = 20;
      o.x.rand_mode(0);
      o.i.rand_mode(0);
      randomize_result = o.randomize();
      `checkd(randomize_result, 1);
      `checkh(o.y, 1'b0);
      randomize_result = o.randomize(null);
      `checkd(randomize_result, 1);
      o.y = 1'b1;
      randomize_result = o.randomize(null);
      `checkd(randomize_result, 0);
    end

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule

// verilator lint_on WIDTH
// verilator lint_on SELRANGE
// verilator lint_on ASCRANGE
