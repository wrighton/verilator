// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0)
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0)
`define checkr(gotv,expv) do if ((gotv) != (expv)) begin $write("%%Error: %s:%0d:  got=%f exp=%f\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0)
// verilog_format: on

// A force keeps evaluating its value (IEEE 1800-2023 10.6.2), also when the forced variable
// can be forced and read through the VPI, as the .vlt files make the variables. The .cpp forces
// and releases some of them through the VPI, and counts value changes of others.

`timescale 1ns / 1ns

module t;
  // A force with a value that keeps changing, under a control that changes
  int vpi_changes = 0;  // Value changes of 'y' seen through the VPI, written by the VPI
  logic src = 1'b0;
  always #1 src = ~src;
  logic drv = 1'b0;
  logic y;
  assign y = drv;
  bit en = 1'b0;
  always @(en) begin
    if (en) force y = src;
    else release y;
  end
  int edges = 0;
  always @(posedge y) ++edges;
  initial begin
    #5 en = 1'b1;
    #49;  // 54 ns: no edge of src at this time
    `checkd(edges, 25);
    // Each of its 49 toggles so far was seen through the VPI too
    `checkd(vpi_changes, 49);
    en = 1'b0;
    #1;
    `checkh(y, drv);
    begin
      automatic int released_edges = edges;
      #4;
      `checkd(edges, released_edges);
    end
  end

  // A force and a release through the VPI override a force in code, as a later force or
  // release does. At 11 ns the VPI forces 'w' to the value it has, and releases it at 17 and
  // 27 ns
  logic [2:0] wsrc = 3'd0;
  always #2 wsrc = wsrc + 3'd1;
  logic [2:0] wdrv = 3'd6;
  logic [2:0] w;
  assign w = wdrv;
  initial begin
    #5 force w = wsrc;
    #8 `checkh(w, 3'd5);
    #2 `checkh(w, 3'd5);
    #4 `checkh(w, wdrv);
    #2 force w = wsrc;
    #2 `checkh(w, wsrc);
    #6 `checkh(w, wdrv);
    #4 `checkh(w, wdrv);
  end

  // A force in code of other bits in the same time step as a force through the VPI (of 'h55
  // at 6 ns) takes only its own bits
  logic [6:0] msrc = 7'd0;
  always #2 msrc = msrc + 7'd9;
  logic [6:0] mdrv = 7'd0;
  logic [6:0] m;
  assign m = mdrv;
  initial begin
    #1 force m[6:3] = msrc[6:3];
    #5 force m[2:0] = msrc[2:0];
    #1 `checkh(m, {4'b1010, msrc[2:0]});
    #2 `checkh(m, {4'b1010, msrc[2:0]});
  end

  // Overlapping and partial forces of a wide variable, each keeping only the bits no later
  // force or release took
  logic [94:0] a = 95'h0;
  logic [94:0] b = 95'h0;
  always #2 a = a + 95'h1234_5678_9abc_def0_1234_5679;
  always #2 b = b - 95'h0fed_cba9_8765_4321_0fed_cba9;
  logic [94:0] vdrv = 95'h5a5a_5a5a_5a5a_5a5a_5a5a_5a5a;
  logic [94:0] v;
  assign v = vdrv;
  initial begin
    #1 force v = a;
    #4 `checkh(v, a);
    force v[70:30] = b[70:30];
    #4 `checkh(v, {a[94:71], b[70:30], a[29:0]});
    release v[70:30];
    #4 `checkh(v, {a[94:71], vdrv[70:30], a[29:0]});
    release v;
    #4 `checkh(v, vdrv);
  end

  // A forced value of a type without bits
  real rsrc = 0.0;
  always #2 rsrc = rsrc + 1.5;
  real rdrv = -1.0;
  real r;
  assign r = rdrv;
  initial begin
    #3 force r = rsrc;
    #6 `checkr(r, rsrc);
    release r;
    #2 `checkr(r, rdrv);
  end

  // A whole forced value of an unpacked type keeps following its value
  typedef struct {
    int a;
    int b;
  } pair_t;
  pair_t psrc;
  pair_t pdrv;
  pair_t p;
  assign p = pdrv;
  initial begin
    pdrv = '{6, 7};
    psrc = '{1, 2};
    #1 force p = psrc;
    #2 psrc = '{3, 4};
    #2 `checkd(p.a, 3);
    `checkd(p.b, 4);
    release p;
    #1 `checkd(p.a, 6);
    `checkd(p.b, 7);
  end

  // A forced real keeps following its value after the value was not a number
  real nsrc = 1.0;
  real ndrv = -1.0;
  real n;
  assign n = ndrv;
  initial begin
    #1 force n = nsrc;
    #2 nsrc = $bitstoreal(64'h7ff8_0000_0000_0000);
    #2 nsrc = 4.0;
    #2 `checkr(n, 4.0);
  end

  // A force of a value that is already forced starts from its forced value
  bit csrc = 1'b1;
  wire ca = 1'b0;
  wire cy = 1'b0;
  initial begin
    #1 force ca = csrc;
    #2 force cy = ca;
    #2 `checkh(cy, 1'b1);
    csrc = 1'b0;
    #2 `checkh(cy, 1'b0);
  end

  // A value change a value change callback makes itself is seen as well: at 31 ns the VPI
  // forces 'c' to 1, and the callback seeing that forces it to 0
  int vpi_c_changes = 0;  // Value changes of 'c' seen through the VPI, written by the VPI
  wire c = 1'b0;
  initial begin
    #1 force c = 1'b0;
    #1 release c;
    #33 `checkd(vpi_c_changes, 2);
    `checkh(c, 1'b0);
  end

  initial begin
    #70;
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
