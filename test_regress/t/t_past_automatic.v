// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module t;
  bit clk = 0;
  always #5 clk = ~clk;
  int cyc = 0;
  always @(negedge clk) cyc <= cyc + 1;

  // The past value of an automatic variable is its current value: $past(b[i]) is bit i of b
  // at the previous tick
  bit [6:0] b = 7'h5a;
  bit [6:0] r;
  bit [6:0] hb = 7'h5a;
  int ri[7];
  initial begin
    #2;
    forever begin
      b = b + 7'h13;
      #10;
    end
  end
  always @(posedge clk) begin
    for (int i = 0; i < 7; i++) begin
      r[i] <= $past(b[i]);
      ri[i] <= $past(i);
    end
  end
  always @(posedge clk) hb <= b;
  always @(posedge clk) begin
    automatic bit [6:0] e = hb;
    #1;
    `checkh(r, e);
    for (int i = 0; i < 7; i++) `checkh(ri[i], i);
  end

  // In a procedural concurrent assertion, after the first tick
  int npass = 0;
  always @(posedge clk) begin
    for (int i = 0; i < 7; i++) begin
      a_b : assert property (cyc == 0 || $past(b[i]) == hb[i]) npass++;
    end
  end

  // Arrays selected by an automatic index, in a loop with a varying bound
  function automatic bit [30:0] f(bit [30:0] x, int k);
    return x ^ 31'(k * 31'h1234567);
  endfunction
  int n = 3;
  bit [30:0] fixd[1:3];
  bit [30:0] fixi[3:1] = '{31'h1111, 31'h2222, 31'h3333};
  bit [30:0] dyn[] = '{31'h4444, 31'h5555, 31'h6666, 31'h7777};
  bit [30:0] que[$] = '{31'h8888, 31'h9999, 31'haaaa, 31'hbbbb};
  bit [30:0] asc[int];
  typedef struct {
    bit [14:0] a;
    int b;
  } us_t;
  us_t sa[1:3];
  bit [30:0] m2[0:1][3:1];
  always @(negedge clk) begin
    for (int j = 1; j <= 3; j++) begin
      fixd[j] <= fixd[j] + 31'(j * 7 + cyc);
      fixi[j] <= fixi[j] ^ 31'(j << cyc);
      dyn[j] = dyn[j] + 31'(cyc);
      que[j] = que[j] - 31'(j + cyc);
      asc[j] = 31'(cyc * j);
      sa[j].a <= sa[j].a + 15'(j + cyc * 3);
      m2[1][j] <= m2[1][j] ^ 31'(cyc << j);
    end
  end
  // Values one, two and three ticks ago, from the default sampled values
  bit [30:0] fixd1[1:3], fixd2[1:3], fixd3[1:3];
  bit [30:0] fixi1[3:1] = '{31'h1111, 31'h2222, 31'h3333};
  bit [30:0] dyn1[] = '{31'h4444, 31'h5555, 31'h6666, 31'h7777};
  bit [30:0] que1[$] = '{31'h8888, 31'h9999, 31'haaaa, 31'hbbbb};
  bit [30:0] asc1[int];
  us_t sa1[1:3];
  bit [30:0] m21[0:1][3:1];
  always @(posedge clk) begin
    fixd1 <= fixd;
    fixd2 <= fixd1;
    fixd3 <= fixd2;
    fixi1 <= fixi;
    dyn1 <= dyn;
    que1 <= que;
    asc1 <= asc;
    sa1 <= sa;
    m21 <= m2;
  end
  always @(posedge clk) begin
    for (int i = 1; i <= n; i++) begin
      `checkh($past(fixd[i]), fixd1[i]);
      `checkh($past(fixd[i], 2), fixd2[i]);
      `checkh($past($past(fixd[i])), fixd2[i]);
      `checkh($past(f(fixd[i], i)), f(fixd1[i], i));
      `checkh($past(fixd[i] + 31'h5), fixd1[i] + 31'h5);
      `checkh($past($past(fixd[1]) ^ fixd[i]), fixd2[1] ^ fixd1[i]);
      `checkh($past($past(fixd[i] + 31'(i)) + 31'(i)), fixd2[i] + 31'(2 * i));
      `checkh($past($past($past(fixd[i] + 31'(i)) + 31'(i)) + 31'(i)), fixd3[i] + 31'(3 * i));
      `checkh($stable(fixd[i]), fixd[i] == fixd1[i]);
      `checkh($changed(fixd[i]), fixd[i] != fixd1[i]);
      `checkh($rose(fixd[i]), fixd[i][0] && !fixd1[i][0]);
      `checkh($fell(fixd[i]), !fixd[i][0] && fixd1[i][0]);
      `checkh($past(fixi[i]), fixi1[i]);
      `checkh($past(dyn[i]), dyn1[i]);
      `checkh($past(que[i]), que1[i]);
      `checkh($past(asc.exists(i) ? asc[i] : 31'h0), asc1.exists(i) ? asc1[i] : 31'h0);
      `checkh($past(sa[i].a), sa1[i].a);
      `checkh($past(m2[1][i]), m21[1][i]);
      `checkh($past(i), i);
      `checkh($sampled(i), i);
      a_fixd : assert property ($past(fixd[i]) == fixd1[i]);
    end
  end

  // In a procedure, value change functions compare sampled values, while an automatic index or
  // variable is read with its current value
  bit [6:0] v = 7'h29;
  bit [6:0] pv = 7'h29;
  always @(posedge clk) begin
    automatic bit [6:0] s = v;  // The sampled value: before the write below
    automatic bit x = s[0];
    v = v + 7'h13;
    for (int i = 0; i < 7; i++) begin
      `checkh($rose(v[i]), s[i] && !pv[i]);
      `checkh($stable(v[i]), s[i] == pv[i]);
    end
    `checkh($rose(x), 1'b0);
    pv = s;
  end

  // The sampled value of a runtime-valued automatic variable, also an argument or a local of an
  // automatic function, is its current value
  function automatic int fs(int x);
    int l;
    l = 2 * x + 1;
    return $sampled(l) + $sampled(x);
  endfunction
  always @(posedge clk) begin
    automatic int la;
    la = 2 * cyc + 1;
    `checkh($sampled(la), 2 * cyc + 1);
    `checkh(fs(cyc + 11), 3 * (cyc + 11) + 1);
  end

  // A class property is not an automatic variable, whatever its lifetime: its past value is its
  // history
  class Cp;
    int v;
    static int sv;
  endclass
  Cp cp = new;
  int hv = 0;
  int hsv = 0;
  always @(negedge clk) begin
    cp.v = cyc * 3;
    Cp::sv = cyc * 5;
  end
  always @(posedge clk) begin
    `checkh($past(cp.v), hv);
    `checkh($past(Cp::sv), hsv);
    hv <= cp.v;
    hsv <= Cp::sv;
  end

  initial begin
    #100;
    `checkh(npass, 70);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
