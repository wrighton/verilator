// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0)
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0)
`define checks(gotv,expv) do if ((gotv) != (expv)) begin $write("%%Error: %s:%0d:  got='%s' exp='%s'\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0)
`define checkp(gotv,expv_s) do begin string gotv_s; gotv_s = $sformatf("%p", gotv); if ((gotv_s) != (expv_s)) begin $write("%%Error: %s:%0d:  got='%s' exp='%s'\n", `__FILE__,`__LINE__, (gotv_s), (expv_s)); `stop; end end while(0)
// verilog_format: on

interface ifc;
  int v;
endinterface

// Slices of unpacked arrays with a variable position (IEEE 1800-2023 7.4.6)
module t (
    input clk
);
  int cyc = 0;

  // Issue reproducer: NBA to a slice, with the position changing every cycle
  localparam int N = 2;
  localparam int D = 4;
  logic [7:0] data[N*D-1:0];
  logic [7:0] w[N-1:0];
  logic [1:0] ptr;
  always_ff @(posedge clk) data[N*ptr+:N] <= w;
  always @(posedge clk) begin
    if (cyc < D) begin
      ptr <= 2'(cyc);
      w[0] <= 8'(2 * cyc);
      w[1] <= 8'(2 * cyc + 1);
    end
    // The value written by the NBA is seen in the next cycle, while ptr has changed
    if (cyc >= 2 && cyc < D + 2) begin
      `checkh(data[N*(cyc-2)], 8'(2 * (cyc - 2)));
      `checkh(data[N*(cyc-2)+1], 8'(2 * (cyc - 2) + 1));
    end
    if (cyc == D + 2) begin
      for (int i = 0; i < N * D; ++i) `checkh(data[i], 8'(i));
    end
  end

  // NBA with +: and -: on descending and ascending arrays with non-zero low bounds
  logic [14:0] nd[10:3];
  logic [14:0] na[3:10];
  int npos;
  always @(posedge clk) begin
    if (cyc == 0) begin
      for (int i = 3; i <= 10; ++i) begin
        nd[i] <= '0;
        na[i] <= '0;
      end
    end else if (cyc < 7) begin
      npos <= cyc + 3;
      nd[npos+:2] <= '{15'(100 + npos), 15'(200 + npos)};
      na[npos-:2] <= '{15'(300 + npos), 15'(400 + npos)};
    end
    if (cyc >= 3 && cyc < 8) begin
      // Written in the previous cycle, with position cyc + 1
      `checkh(nd[cyc+2], 15'(100 + cyc + 1));
      `checkh(nd[cyc+1], 15'(200 + cyc + 1));
      `checkh(na[cyc], 15'(300 + cyc + 1));
      `checkh(na[cyc+1], 15'(400 + cyc + 1));
    end
  end

  // Blocking reads and writes
  logic [69:0] bd[10:3];
  logic [69:0] ba[3:10];
  logic [69:0] r3[2:0];
  logic [69:0] r3a[0:2];
  always @(posedge clk) begin
    for (int i = 3; i <= 10; ++i) begin
      bd[i] = {6'(i), 64'h1234_5678_9abc_def0};
      ba[i] = {6'(i), 64'h0fed_cba9_8765_4321};
    end
    if (cyc >= 2 && cyc <= 7) begin
      // Read +: descending; the left element is the highest index
      r3 = bd[cyc+1+:3];
      `checkh(r3[2], {6'(cyc + 3), 64'h1234_5678_9abc_def0});
      `checkh(r3[0], {6'(cyc + 1), 64'h1234_5678_9abc_def0});
      // Read -: ascending; the left element is the lowest index
      r3a = ba[cyc+3-:3];
      `checkh(r3a[0], {6'(cyc + 1), 64'h0fed_cba9_8765_4321});
      `checkh(r3a[2], {6'(cyc + 3), 64'h0fed_cba9_8765_4321});
      // Equality, and passing as an argument
      `checkh(bd[cyc+1+:3] == r3, 1'b1);
      `checkh(bd[cyc+:3] != r3, 1'b1);
      `checkh(top6(ba[cyc+1+:3]), 6'(cyc + 1));
      // Write -: descending, +: ascending
      bd[cyc+3-:3] = '{70'd1, 70'd2, 70'(cyc)};
      `checkh(bd[cyc+3], 70'd1);
      `checkh(bd[cyc+1], 70'(cyc));
      ba[cyc+1+:3] = '{70'd4, 70'd5, 70'(cyc)};
      `checkh(ba[cyc+1], 70'd4);
      `checkh(ba[cyc+3], 70'(cyc));
    end
  end
  function automatic logic [5:0] top6(logic [69:0] a[0:2]);
    return a[0][69:64];
  endfunction

  // As a bare value, and spliced into an unpacked array concatenation
  int pv[5];
  int pos2;
  int cat[4];
  always @(posedge clk) begin
    if (cyc == 1) begin
      pv = '{10, 11, 12, 13, 14};
      pos2 = 1;
    end else if (cyc == 2) begin
      `checkp(pv[pos2+:3], "'{'hb, 'hc, 'hd}");
      cat = {pv[pos2+1+:2], pv[pos2-:2]};
      `checkp(cat, "'{'hc, 'hd, 'ha, 'hb}");
    end
  end

  // A slice not entirely within the array is treated as an invalid index (IEEE 1800-2023
  // 7.4.6), so reads give the initial value of the type and writes are ignored
  int ov[8:1];
  int ovr[3];
  int opos;
  logic [63:0] owide;
  logic [69:0] owider;
  string os[3];
  string osr[2];
  always @(posedge clk) begin
    if (cyc == 1) begin
      for (int i = 1; i <= 8; ++i) ov[i] = i;
      os = '{"a", "b", "c"};
      opos = 7;
      owide = 64'h1_0000_0002;
      owider = 70'h1_0000_0000_0000_0003;
    end else if (cyc == 2) begin
      ovr = ov[opos-1+:3];  // Whole slice within the array
      `checkp(ovr, "'{'h8, 'h7, 'h6}");
      ovr = ov[opos+:3];  // Partially out of range
      `checkp(ovr, "'{'h0, 'h0, 'h0}");
      ovr = ov[opos-8+:3];  // Below the low bound
      `checkp(ovr, "'{'h0, 'h0, 'h0}");
      ovr = ov[-opos+:3];  // Negative
      `checkp(ovr, "'{'h0, 'h0, 'h0}");
      ovr = ov[owide+:3];  // Position above 32 bits, must not alias position 2
      `checkp(ovr, "'{'h0, 'h0, 'h0}");
      `checkp(ov[owider+:3], "'{'h0, 'h0, 'h0}");  // Above 64 bits
      ovr = ov[70'(opos-4)+:3];
      `checkp(ovr, "'{'h5, 'h4, 'h3}");
      `checkd(oob_sum(opos + 1), 0);
      `checkd(oob_sum(opos - 6), 3);
      osr = os[opos-6+:2];
      `checks(osr[0], "b");
      `checks(osr[1], "c");
      osr = os[opos+:2];
      `checks(osr[0], "");
      `checks(osr[1], "");
      ov[opos+:3] = '{100, 101, 102};
      ov[-opos+:3] = '{100, 101, 102};
      ov[owide+:3] = '{100, 101, 102};
      ov[owider+:3] = '{100, 101, 102};
      for (int i = 1; i <= 8; ++i) `checkd(ov[i], i);
      // NBA out of range
      ov[opos+:3] <= '{100, 101, 102};
    end else if (cyc == 3) begin
      for (int i = 1; i <= 8; ++i) `checkd(ov[i], i);
    end
  end
  function automatic int oob_sum(int p);
    int s[2];
    s = ov[p+:2];
    return s[0] + s[1];
  endfunction

  // Narrow position, slice of a multi-dimensional array and of a structure member
  typedef struct {
    byte arr[2:7];
    int n;
  } s_t;
  s_t s;
  byte m[3][1:6];
  logic [1:0] narrow;
  always @(posedge clk) begin
    if (cyc == 1) begin
      for (int i = 2; i <= 7; ++i) s.arr[i] = 8'(i);
      for (int i = 0; i < 3; ++i) for (int j = 1; j <= 6; ++j) m[i][j] = 8'(10 * i + j);
      narrow = 2'd3;
    end else if (cyc == 2) begin
      `checkp(s.arr[narrow+:4], "'{'h3, 'h4, 'h5, 'h6}");
      s.arr[narrow+1+:2] = '{8'd40, 8'd50};
      `checkp(s.arr, "'{'h2, 'h3, 'h28, 'h32, 'h6, 'h7}");
      `checkp(m[narrow-1][narrow+:3], "'{'h17, 'h18, 'h19}");
      m[narrow-2][narrow-:2] = '{8'd0, 8'd1};
      `checkp(m[1], "'{'hb, 'h0, 'h1, 'he, 'hf, 'h10}");
      `checkp(m[narrow-2+:2],
              "'{'{'hb, 'h0, 'h1, 'he, 'hf, 'h10}, '{'h15, 'h16, 'h17, 'h18, 'h19, 'h1a}}");
    end
  end

  // An element of a slice, and a stream of a slice of structures, are elements of the sliced
  // array; a slice partly out of range is invalid as a whole, as above
  typedef struct {byte b;} sb_t;
  sb_t sb[1:5];
  int el[5];
  int ed[4:0];
  int epos;
  logic [15:0] epk;
  always @(posedge clk) begin
    if (cyc == 1) begin
      for (int i = 1; i <= 5; ++i) begin
        el[i-1] = i;
        ed[i-1] = i;
        sb[i].b = 8'(i);
      end
      epos = 2;
    end else if (cyc == 2) begin
      el[1:3][2] = 30;
      `checkp(el, "'{'h1, 'h2, 'h1e, 'h4, 'h5}");
      `checkd(el[2:4][4], 5);
      el[0:2][epos] = 33;  // Variable index
      `checkd(el[2], 33);
      `checkd(el[1:3][epos+1], 4);
      ed[3:1][2] = 32;  // Descending
      ed[3:1][epos-1] = 31;
      `checkd(ed[1], 31);
      `checkd(ed[2], 32);
      `checkd(ed[3], 4);
      `checkd(ed[4:2][epos+2], 5);
      el[0:3][1:2][1] = 34;  // Slice of a slice
      `checkd(el[1], 34);
      `checkd(el[0:3][1:2][2], 33);
      {>>{sb[epos+:2]}} = 16'h1234;
      `checkh(sb[1].b, 8'h1);
      `checkh(sb[2].b, 8'h12);
      `checkh(sb[3].b, 8'h34);
      `checkh(sb[4].b, 8'h4);
      epk = {>>{sb[epos+1+:2]}};
      `checkh(epk, 16'h3404);
      epos = 5;
      {>>{sb[epos+:2]}} = 16'h5678;
      `checkh(sb[5].b, 8'h5);
      epk = {>>{sb[epos+:2]}};
      `checkh(epk, 16'h0);
    end
  end

  // Combinational logic
  bit [4:0] cin[2];
  bit [4:0] cout[1:6];
  bit [4:0] cw[2];
  int csel;
  always_comb begin
    cout = '{default: 5'd31};
    cout[csel+:2] = cin;
  end
  assign cw = cout[csel+1-:2];
  always @(posedge clk) begin
    csel <= cyc;
    cin <= '{5'(cyc), 5'(cyc + 10)};
    if (cyc >= 2 && cyc <= 5) begin
      // csel is cyc - 1
      `checkh(cout[cyc-1], 5'(cyc - 1));
      `checkh(cout[cyc], 5'(cyc + 9));
      `checkh(cout[cyc+1], 5'd31);
      `checkh(cw[0], 5'(cyc - 1));
      `checkh(cw[1], 5'(cyc + 9));
    end else if (cyc == 7) begin
      // Out of range
      `checkp(cout, "'{'h1f, 'h1f, 'h1f, 'h1f, 'h1f, 'h1f}");
      `checkp(cw, "'{'h0, 'h0}");
    end
  end

  // Continuous assignment to a slice
  bit [4:0] aout[4];
  int asel;
  assign aout[asel+:2] = cin;
  always @(posedge clk) begin
    asel <= cyc - 2;
    if (cyc >= 3 && cyc <= 4) begin
      // asel is cyc - 3, cin was set in cycle cyc - 1
      `checkh(aout[cyc-3], 5'(cyc - 1));
      `checkh(aout[cyc-2], 5'(cyc + 9));
    end
  end

  // Slice of an array of interface instances, at a position from a constant function
  ifc ifs[4] ();
  virtual ifc vifs[2];
  function automatic int ident(int x);
    return x;
  endfunction
  initial begin
    ifs[0].v = 10;
    ifs[1].v = 11;
    ifs[2].v = 12;
    ifs[3].v = 13;
    vifs = ifs[ident(2)+:2];
    `checkd(vifs[0].v, 12);
    `checkd(vifs[1].v, 13);
  end

  // Position with a side effect is evaluated once
  int calls = 0;
  int sv[6];
  int svr[2];
  function automatic int next_pos();
    ++calls;
    return calls;
  endfunction
  always @(posedge clk) begin
    if (cyc == 1) begin
      sv = '{0, 1, 2, 3, 4, 5};
      svr = sv[next_pos()+:2];
      `checkp(svr, "'{'h1, 'h2}");
      `checkd(calls, 1);
      sv[next_pos()+:2] = '{20, 30};
      `checkp(sv, "'{'h0, 'h1, 'h14, 'h1e, 'h4, 'h5}");
      `checkd(calls, 2);
    end
  end

  // Narrow and signed narrow positions with a zero low bound, slice of a constant
  localparam int CONSTS[6] = '{10, 11, 12, 13, 14, 15};
  logic [1:0] zpos;
  byte spos;
  int nr[2];
  always @(posedge clk) begin
    if (cyc == 1) begin
      zpos = 2'd3;
      spos = -1;
    end else if (cyc == 2) begin
      nr = CONSTS[zpos+:2];
      `checkp(nr, "'{'hd, 'he}");
      nr = CONSTS[spos+:2];
      `checkp(nr, "'{'h0, 'h0}");
    end
  end

  // Slice of a class member
  class Cls;
    int a[6];
  endclass
  Cls cls;
  int cpos;
  always @(posedge clk) begin
    if (cyc == 1) begin
      cls = new;
      cls.a = '{1, 2, 3, 4, 5, 6};
      cpos = 1;
    end else if (cyc == 2) begin
      cls.a[cpos+:2] = '{7, 8};
      cls.a[cpos+5+:2] = '{9, 9};
      `checkp(cls.a, "'{'h1, 'h7, 'h8, 'h4, 'h5, 'h6}");
    end
  end

  // In a constant function
  function automatic int sum_slice(int p);
    int sl[3];
    sl = CONSTS[p+:3];
    return sl[0] + sl[1] + sl[2];
  endfunction
  localparam int SUM = sum_slice(2);
  initial `checkd(SUM, 39);

  always @(posedge clk) begin
    cyc <= cyc + 1;
    if (cyc == 10) begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
