// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Type checks of typeless mailbox messages, using only the methods that do not block

// verilator lint_off DECLFILENAME
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); $stop; end while(0);
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); $stop; end while(0);
`define checks(gotv,expv) do if ((gotv) != (expv)) begin $write("%%Error: %s:%0d:  got='%s' exp='%s'\n", `__FILE__,`__LINE__, (gotv), (expv)); $stop; end while(0);

package p1;
  class Item;
    int a;
  endclass
endpackage

package p2;
  class Item;
    string s;
  endclass
endpackage

typedef enum {
  RED,
  GREEN
} color_t;

typedef struct packed {
  bit [15:0] hi;
  bit [15:0] lo;
} pair_t;

typedef int int_t;

class Base;
  int id;
endclass

class Derived extends Base;
endclass

module t;
  mailbox m = new;

  initial begin
    begin : basic
      int i;
      string s;
      // Each message is taken only by a variable of an equivalent type
      i = 5;
      `checkd(m.try_put(i), 1);
      s = "hello";
      `checkd(m.try_put(s), 1);
      `checkd(m.num(), 2);
      `checkd(m.try_get(s), -1);
      `checkd(m.try_peek(s), -1);
      `checkd(m.num(), 2);
      i = 0;
      `checkd(m.try_peek(i), 1);
      `checkd(i, 5);
      i = 0;
      `checkd(m.try_get(i), 1);
      `checkd(i, 5);
      `checkd(m.try_get(i), -1);
      s = "";
      `checkd(m.try_get(s), 1);
      `checks(s, "hello");
      `checkd(m.num(), 0);
      `checkd(m.try_get(i), 0);
      `checkd(m.try_peek(i), 0);
    end
    begin : packed_types
      int i;
      integer i4;
      bit [31:0] bu32;
      bit signed [31:0] bs32;
      int_t it;
      pair_t pair;
      // 2-state signed 32 bits: int, typedef of int, bit signed [31:0]
      i = 6;
      void'(m.try_put(i));
      `checkd(m.try_get(i4), -1);  // 4-state
      `checkd(m.try_get(bu32), -1);  // Unsigned
      `checkd(m.try_get(it), 1);
      `checkd(it, 6);
      it = 7;
      void'(m.try_put(it));
      `checkd(m.try_get(bs32), 1);
      `checkd(bs32, 7);
      // A literal without X or Z is 2-state
      void'(m.try_put(8));
      `checkd(m.try_get(i4), -1);
      `checkd(m.try_get(i), 1);
      `checkd(i, 8);
      // Packed struct and packed array of the same size, signing and state
      pair = '{hi: 16'h1234, lo: 16'h5678};
      void'(m.try_put(pair));
      `checkd(m.try_get(bu32), 1);
      `checkh(bu32, 32'h1234_5678);
    end
    begin : clean
      bit [4:0] b5;
      logic [99:0] w;
      logic [69:0] w70;
      // Bits above the width of the message expression are not kept
      b5 = 5'd30;
      void'(m.try_put(b5 + 5'd3));
      `checkd(m.try_get(b5), 1);
      `checkd(b5, 1);
      w = {100{1'b1}};
      void'(m.try_put(w + 100'd1));
      void'(m.try_put(w[69:0]));
      `checkd(m.try_get(w70), -1);
      `checkd(m.try_get(w), 1);
      `checkh(w, 100'h0);
      `checkd(m.try_get(w70), 1);
      `checkh(w70, {70{1'b1}});
    end
    begin : enums
      enum {A, B} e1;
      enum {C, D} e2;
      color_t c;
      int i;
      // An enum type is only equivalent to itself
      c = GREEN;
      void'(m.try_put(c));
      `checkd(m.try_get(i), -1);
      `checkd(m.try_get(e1), -1);
      c = RED;
      `checkd(m.try_get(c), 1);
      `checkd(c, GREEN);
      void'(m.try_put(GREEN));  // Enum constant
      `checkd(m.try_get(i), -1);
      c = RED;
      `checkd(m.try_get(c), 1);
      `checkd(c, GREEN);
      e1 = B;
      void'(m.try_put(e1));
      `checkd(m.try_get(e2), -1);
      e1 = A;
      `checkd(m.try_get(e1), 1);
      `checkd(e1, B);
    end
    begin : others
      real r;
      chandle ch;
      string s;
      r = 1.5;
      void'(m.try_put(r));
      ch = null;
      void'(m.try_put(ch));
      `checkd(m.try_get(ch), -1);
      r = 0;
      `checkd(m.try_get(r), 1);
      `checkd(r == 1.5, 1'b1);
      `checkd(m.try_get(r), -1);
      `checkd(m.try_get(ch), 1);
      `checkd(ch == null, 1'b1);
      void'(m.try_put(r));
      s = $sformatf("%p", m);
      `checkd(s.len() > 0, 1'b1);
      `checkd(m.try_get(r), 1);
    end
    begin : classes
      Base b;
      Derived d;
      p1::Item it1;
      p2::Item it2;
      // A class type is only equivalent to itself
      d = new;
      d.id = 7;
      void'(m.try_put(d));
      `checkd(m.try_get(b), -1);
      `checkd(m.try_get(d), 1);
      `checkd(d.id, 7);
      // Different classes with the same name
      it1 = new;
      it1.a = 9;
      void'(m.try_put(it1));
      `checkd(m.try_get(it2), -1);
      `checkd(m.try_get(it1), 1);
      `checkd(it1.a, 9);
      `checkd(m.num(), 0);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
