// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// verilator lint_off WIDTH
class UnsignedBounds;
  rand bit signed [7:0] x;
  constraint c {
    x inside {[9'd0 : 9'd300]};
    x < 0;
  }
endclass

class UnsignedValue;
  rand bit signed [7:0] x;
  constraint c {x inside {9'd245};}
endclass

class Mixed;
  rand bit signed [3:0] s;
  rand bit [3:0] u;
  rand bit signed [7:0] n;
  rand bit m;
  constraint c {
    s inside {[-5'sd6 : 5'sd4]};
    u inside {[2'sd1 : 9'd300]};
    !(n inside {[9'd0 : 9'd250]});
    m -> s inside {[-3 : -1]};
  }
endclass

module t;
  int ok;

  initial begin
    begin
      UnsignedBounds c;
      c = new;
      repeat (8) begin
        ok = c.randomize();
        `checkd(ok, 1);
        `checkd(c.x < 0, 1'b1);
      end
    end
    begin
      UnsignedValue c;
      c = new;
      ok = c.randomize();
      `checkd(ok, 1);
      `checkd(c.x, -11);
    end
    begin
      Mixed c;
      int neg_s;
      int neg_u;
      c = new;
      neg_s = 0;
      repeat (40) begin
        ok = c.randomize();
        `checkd(ok, 1);
        `checkd(c.s >= -5'sd6 && c.s <= 5'sd4, 1'b1);
        `checkd(c.n < 0 && c.n >= -5, 1'b1);
        if (c.m) `checkd(c.s >= -3 && c.s <= -1, 1'b1);
        if (c.s < 0) ++neg_s;
      end
      `checkd(neg_s > 0, 1'b1);
      ok = c.randomize() with {u > 4'd14;};
      `checkd(ok, 1);
      `checkd(c.u, 15);
    end

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
