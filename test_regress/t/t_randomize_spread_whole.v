// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Few values ruled out: the elements pinned to one of them conflict alone, the others fit
class Ones;
  rand bit [7:0] d[];
  constraint c {
    d.size() == 2000;
    foreach (d[i]) d[i] != 8'd0;
  }
endclass

// Most values ruled out: nearly every element conflicts
class Below;
  rand bit [7:0] d[];
  constraint c {
    d.size() == 2000;
    foreach (d[i]) d[i] < 8'd10;
  }
endclass

// Many values ruled out, yet a few samples all fit: the elements that conflict must not
// spend every check one by one, which would leave the first solution, nearly all zeros
class Most;
  rand bit [7:0] d[];
  constraint c {
    d.size() == 3000;
    foreach (d[i]) d[i] < 8'd200;
  }
endclass

module t;
  initial begin
    automatic Ones o = new;
    automatic Below b = new;
    automatic Most m = new;
    automatic int seen[int];
    automatic int ok;
    automatic int ones = 0;
    o.srandom(1);
    b.srandom(1);
    m.srandom(1);
    ok = o.randomize();
    `checkd(ok, 1);
    foreach (o.d[i]) begin
      `checkd(o.d[i] != 8'd0, 1'b1);
      seen[int'(o.d[i])] = 1;
    end
    `checkd(seen.num() > 200, 1'b1);
    seen.delete();
    ok = b.randomize();
    `checkd(ok, 1);
    foreach (b.d[i]) begin
      `checkd(b.d[i] < 8'd10, 1'b1);
      seen[int'(b.d[i])] = 1;
    end
    `checkd(seen.num(), 10);
    seen.delete();
    ok = m.randomize();
    `checkd(ok, 1);
    foreach (m.d[i]) begin
      `checkd(m.d[i] < 8'd200, 1'b1);
      seen[int'(m.d[i])] = 1;
      ones += $countones(m.d[i]);
    end
    `checkd(seen.num() > 150, 1'b1);
    // Of 24000 bits, near half are set (46% for values below 200)
    `checkd(ones > 9000 && ones < 14000, 1'b1);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
