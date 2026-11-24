// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2022 Antmicro Ltd
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

class Cls;
  int val = 0;
  int w = 0;
  function int get_w();
    return w;
  endfunction
endclass

class VBase;
  int w = 0;
  virtual function int get_w();
    return w;
  endfunction
endclass

class VDerived extends VBase;
  function int get_w();
    return w + 100;
  endfunction
endclass

module sub(input logic clk  /*verilator public_flat_rw*/, output int cnt);
  initial cnt = 0;
  always @(posedge clk) cnt <= cnt + 1;
endmodule

module top;
  logic v;
  int num;
  time t;

  initial begin
    num = 1;
    #1;
    if (v) $stop;
    num = 21;
    t = $time;
    // Zero delay postpones the execution until after the combinational logic updating `v`
    #0;
    if (!v) $stop;
    if (t != $time) $stop;
    #1;  // After the checks of the other initial blocks
    $write("*-* All Finished *-*\n");
    $finish;
  end

  always_comb v = (num == 21);

  // A value written after a zero delay reaches the logic reading it before the next zero delay
  int x = 0;
  int y;
  assign y = x + 1;
  initial begin
    #1 x = 5;
    #0 `checkd(y, 6);
    x = 7;
    #0 `checkd(y, 8);
    #0 x = 9;
    #0 `checkd(y, 10);
  end

  // Likewise for an unpacked array and an event, and a value a process waiting on that event
  // writes
  int ua[2] = '{0, 0};
  int uidx = 1;
  int uy;
  assign uy = ua[uidx] + 1;
  event e;
  int ecnt = 0;
  always @(e) ecnt++;
  int w = 0;
  int wy;
  assign wy = w + 1;
  initial begin
    @(e) w = 3;
  end
  initial begin
    #1;
    #0 ua[uidx] = 4;
    #0 `checkd(uy, 5);
    #0 ->e;
    #0 `checkd(ecnt, 1);
    `checkd(wy, 4);
  end

  // Likewise for a class member, also read through a method, a real array element changing to
  // -0.0, a write in a loop condition and a write through a task's ref argument before the
  // task's zero delay
  Cls c = new;
  int cy;
  always_comb cy = c.val + 1;
  int cwy;
  always_comb cwy = c.get_w() + 1;
  VBase vb;
  int vy;
  always_comb vy = vb == null ? 0 : vb.get_w();
  real ra[2] = '{0.0, 0.0};
  bit [63:0] rbits;
  assign rbits = $realtobits(ra[uidx]);
  int lx = 0;
  int ln = 0;
  int ly;
  assign ly = lx + 1;
  function automatic int next(output int v);
    ++ln;
    v = ln;
    return ln;
  endfunction
  int ref_v = 0;
  int ref_y;
  assign ref_y = ref_v + 1;
  task automatic set_then_wait(ref int v);
    v = 9;
    #0;
  endtask
  initial begin
    #1;
    #0 c.val = 4;
    #0 `checkd(cy, 5);
    c.w = 6;
    #0 `checkd(cwy, 7);
    begin
      automatic VDerived vd = new;
      vb = vd;
      #0 vd.w = 3;
      #0 `checkd(vy, 103);
    end
    #0 ra[uidx] = -0.0;
    #0 `checkh(rbits, 64'h8000_0000_0000_0000);
    while (next(lx) < 3) begin
      #0 `checkd(ly, lx + 1);
    end
    set_then_wait(ref_v);
    `checkd(ref_y, 10);
  end

  // So does a clock edge made after a zero delay, through a publicly writable variable, a
  // submodule port or a variable of this module
  logic clk = 0;
  logic clk_pub  /*verilator public_flat_rw*/;
  int cnt_sub;
  int cnt_top = 0;
  sub u_sub (
      .clk,
      .cnt(cnt_sub)
  );
  assign clk_pub = clk;
  always @(posedge clk_pub) cnt_top <= cnt_top + 1;
  initial begin
    #0 clk = 1;
    #1;
    `checkd(cnt_sub, 1);
    `checkd(cnt_top, 1);
  end
endmodule
