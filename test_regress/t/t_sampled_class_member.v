// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define checks(gotv,expv) do if ((gotv) != (expv)) begin $write("%%Error: %s:%0d:  got='%s' exp='%s'\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

class Inner;
  int w;
endclass

class Cls;
  int v;
  bit b;
  string s;
  Inner inner;
  static Cls sh;
endclass

class Init;
  int v = 3;
endclass

package pkg;
  Cls ph;
endpackage

// The sampled value of a class property read through a handle is the property of the object
// of the handle's sampled value, in the Preponed region (IEEE 1800-2023 16.5.1)
module t (
    input clk
);

  int cyc = 0;
  Cls c = new;
  Cls c2 = new;
  Cls carr[2];
  Cls stable = new;
  Cls stables[2];
  Init ci = new;
  Init ia0 = new;
  Init ia1 = new;
  Init iarr[2] = '{ia0, ia1};
  int idx = 1;

  function automatic int sampledThrough(Cls h);
    return $sampled(h.v);
  endfunction

  initial begin
    c.inner = new;
    c2.inner = new;
    Cls::sh = new;
    pkg::ph = new;
    carr[0] = new;
    carr[1] = new;
    stable.v = 7;
    stables[1] = stable;
    // At time 0 a class property has the default value of its type
    ci.v = 5;
    `checkd($sampled(ci.v), 0);
  end

  always @(posedge clk) begin
    // Written before the sampled values are read, which are the values before the clock
    if (c != null) begin
      c.v = cyc + 10;
      c.b = cyc[0];
      c.inner.w = cyc + 100;
      c.s = $sformatf("s%0d", cyc);
    end
    carr[0].v = cyc + 40;
    carr[1].v = cyc + 50;
    Cls::sh.v = cyc + 20;
    pkg::ph.v = cyc + 30;
    // Before any history, as only the handles are sampled
    if (cyc == 0) `checkd($past(iarr[idx].v), 3);
    if (cyc >= 1 && cyc <= 3) begin
      `checkd($sampled(c.v), cyc + 9);
      `checkd($past(c.v), cyc == 1 ? 0 : cyc + 8);
      `checkd($changed(c.v), 1'b1);
      `checkd($stable(c.v), 1'b0);
      `checkd($rose(c.b), cyc == 2);
      `checkd($fell(c.b), cyc == 3);
      `checkd($sampled(c.inner.w), cyc + 99);
      `checkd($sampled(Cls::sh.v), cyc + 19);
      `checkd($sampled(pkg::ph.v), cyc + 29);
      // Handles constructed by a process, so null when the history is initialized
      `checkd($past(Cls::sh.v), cyc == 1 ? 0 : cyc + 18);
      `checkd($past(pkg::ph.v, 2), cyc <= 2 ? 0 : cyc + 27);
      `checkd($past(c.inner.w), cyc == 1 ? 0 : cyc + 98);
      `checks($sampled(c.s), $sformatf("s%0d", cyc - 1));
      // Through constant index elements of a static array of handles
      `checkd($sampled(carr[0].v), cyc + 39);
      `checkd($past(carr[1].v), cyc == 1 ? 0 : cyc + 48);
      // Through an automatic variable or a variable index, the property is read when used
      `checkd(sampledThrough(stable), 7);
      `checkd($sampled(stables[idx].v), 7);
    end
    if (cyc == 4) begin
      c2.v = 77;
      c = c2;
      // The sampled handle is still the first object
      `checkd($sampled(c.v), 13);
    end
    if (cyc == 5) begin
      `checkd($sampled(c.v), 77);
      `checkd($past(c.v), 13);
      c = null;
    end
    // A null handle at sampling time gives the default value
    if (cyc == 6) begin
      `checkd($sampled(c.v), 0);
      `checkd($sampled(c.inner.w), 0);
      `checks($sampled(c.s), "");
      `checkd($past(c.v), 77);
    end
    if (cyc == 7) begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
    cyc <= cyc + 1;
  end
endmodule
