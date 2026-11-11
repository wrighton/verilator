// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2024 Antmicro
// SPDX-License-Identifier: CC0-1.0

`define check_rand(cl, field, cond) \
begin \
   automatic longint prev_result; \
   automatic int ok; \
   if (!bit'(cl.randomize())) $stop; \
   prev_result = longint'(field); \
   if (!(cond)) $stop; \
   repeat(9) begin \
      longint result; \
      if (!bit'(cl.randomize())) $stop; \
      result = longint'(field); \
      if (!(cond)) $stop; \
      if (result != prev_result) ok = 1; \
      prev_result = result; \
   end \
   if (ok != 1) $stop; \
end

typedef class C;

class D extends C;
  constraint x_lt_y { x < y; }
endclass

class A;
endclass

class B extends A;
  rand int x;
  constraint x_gt_0 { x > 0; }
endclass

class C extends B;
  rand int y;
endclass

class E extends C;
  constraint x_lt_20 { x < 20; }
  constraint x_gt_y { x > y; }
endclass

// Each constraint binds to the member of its declaring class (IEEE 1800-2023 8.14).
class ShadowBase;
  rand bit [15:0] addr;
  constraint base_c { addr inside {[16'h0100:16'h01ff]}; }
endclass

class ShadowDerived extends ShadowBase;
  rand bit [15:0] addr;
  constraint derived_c { addr inside {[16'h8000:16'h80ff]}; }
endclass

class ShadowMore extends ShadowDerived;
  rand bit [6:0] addr;
  constraint more_c { addr inside {[7'h40:7'h5f]}; }
endclass

// A state member hiding a rand member is not renamed or randomized.
class StateShadow extends ShadowBase;
  bit [15:0] addr = 16'hbeef;
  constraint state_c { addr == 16'hbeef; }
endclass

// A sibling without a redeclaration still uses the base member.
class ShadowSibling extends ShadowBase;
  constraint sibling_c { addr < 16'h0180; }
endclass

module t;
  initial begin
    automatic B b = new;
    automatic C c = new;
    automatic D d = new;
    automatic E e = new;
    automatic A a = b;
    `check_rand(a, b.x, b.x > 0);
    `check_rand(c, c.x, c.x > 0);
    `check_rand(c, c.y, c.x > 0);
    `check_rand(d, d.x, d.x > 0 && d.x < d.y);
    `check_rand(d, d.y, d.x > 0 && d.x < d.y);
    `check_rand(e, e.x, e.x > 0 && e.x < 20 && e.x > e.y);
    `check_rand(e, e.y, e.x > 0 && e.x < 20 && e.x > e.y);
    begin
      automatic ShadowDerived sd = new;
      automatic ShadowBase sb = sd;
      // Twenty calls, through both the derived and base handles.
      `check_rand(sd, sd.addr, sd.addr inside {[16'h8000:16'h80ff]} && sb.addr inside {[16'h0100:16'h01ff]});
      `check_rand(sb, sb.addr, sd.addr inside {[16'h8000:16'h80ff]} && sb.addr inside {[16'h0100:16'h01ff]});
      sd.addr.rand_mode(0);
      sd.addr = 16'h8080;
      `check_rand(sd, sb.addr, sd.addr == 16'h8080 && sb.addr inside {[16'h0100:16'h01ff]});
    end
    begin
      automatic ShadowMore sm = new;
      automatic ShadowDerived sd = sm;
      automatic ShadowBase sb = sm;
      `check_rand(sm, sm.addr, sm.addr inside {[7'h40:7'h5f]} && sd.addr inside {[16'h8000:16'h80ff]} && sb.addr inside {[16'h0100:16'h01ff]});
    end
    begin
      automatic StateShadow ss = new;
      automatic ShadowBase sb = ss;
      `check_rand(ss, sb.addr, ss.addr == 16'hbeef && sb.addr inside {[16'h0100:16'h01ff]});
    end
    begin
      automatic ShadowSibling ss = new;
      `check_rand(ss, ss.addr, ss.addr inside {[16'h0100:16'h017f]});
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
