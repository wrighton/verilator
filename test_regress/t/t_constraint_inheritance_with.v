// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2024 Antmicro
// SPDX-License-Identifier: CC0-1.0

`define check_rand(cl, field, constr, cond) \
begin \
   automatic longint prev_result; \
   automatic int ok; \
   if (!bit'(cl.randomize() with { constr; })) $stop; \
   prev_result = longint'(field); \
   if (!(cond)) $stop; \
   repeat(9) begin \
      longint result; \
      if (!bit'(cl.randomize() with { constr; })) $stop; \
      result = longint'(field); \
      if (!(cond)) $stop; \
      if (result != prev_result) ok = 1; \
      prev_result = result; \
   end \
   if (ok != 1) $stop; \
end

typedef class C;

class D extends C;
  rand int z;
  constraint x_lt_y { x < y; }
endclass

class A;
  rand int x;
endclass

class B extends A;
  constraint x_gt_0 { x > 0; }
endclass

class C extends B;
  rand int y;
endclass

class E extends C;
  constraint x_gt_y { x > y; }
endclass

// Inline constraints must keep hidden members distinct as well.
class ShadowBase;
  rand bit [15:0] addr;
  constraint base_c { addr inside {[16'h0100:16'h01ff]}; }
endclass

class ShadowDerived extends ShadowBase;
  rand bit [15:0] addr;
  constraint derived_c { addr inside {[16'h8000:16'h80ff]}; }
endclass

module t;
  initial begin
    automatic B b = new;
    automatic C c = new;
    automatic D d = new;
    automatic E e = new;
    automatic A a = b;
    `check_rand(a, a.x, x < 10, a.x > 0 && a.x < 10);
    `check_rand(c, c.x, x < 100, c.x > 0 && c.x < 100);
    `check_rand(c, c.y, x == 5, c.x == 5);
    `check_rand(d, d.x, z > x && z < y, d.x > 0 && d.x < d.y);
    `check_rand(d, d.y, z > x && z < y, d.x > 0 && d.x < d.y);
    `check_rand(e, e.x, x inside {[10:20]}, e.x inside {[10:20]} && e.x > e.y);
    `check_rand(e, e.y, x inside {[10:20]}, e.x inside {[10:20]} && e.x > e.y);
    begin
      automatic ShadowDerived sd = new;
      automatic ShadowBase sb = sd;
      `check_rand(sd, sd.addr, addr < 16'h8040, sd.addr inside {[16'h8000:16'h803f]} && sb.addr inside {[16'h0100:16'h01ff]});
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
