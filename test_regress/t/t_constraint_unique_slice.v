// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// The elements of an array slice in a 'unique' constraint are members of the
// group (IEEE 1800-2023 18.5.4).

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0)
// verilog_format: on

typedef bit [2:0] val_t;

// Checks that no two of 'vals' are equal
class Check #(
    type T = val_t
);
  static function void distinct(T vals[$], int line);
    foreach (vals[i])
    foreach (vals[j])
    if (i < j && vals[i] == vals[j]) begin
      $write("%%Error: %s:%0d: members %0d and %0d both hold %0d\n", `__FILE__, line, i, j,
             vals[i]);
      `stop;
    end
  endfunction
endclass

// The example of IEEE 1800-2023 18.5.4
class Lrm;
  rand byte a[5];
  rand byte b;
  rand byte excluded;
  constraint u {unique {b, a[2:3], excluded};}
  constraint exclusion {excluded == 5;}
endclass

// With 5 excluded, only 3, 4 and 6 are left for three members
class LrmFits extends Lrm;
  constraint narrow {
    b inside {[3 : 6]};
    a[2] inside {[3 : 6]};
    a[3] inside {[3 : 6]};
  }
endclass

// With 5 excluded, only 4 and 6 are left for three members
class LrmCollides extends Lrm;
  constraint narrow {
    b inside {[4 : 6]};
    a[2] inside {[4 : 6]};
    a[3] inside {[4 : 6]};
  }
endclass

// Slices of arrays with non-zero bounds in both directions
class Slices;
  rand val_t s;
  rand val_t up[3:7];
  rand val_t down[7:3];
  constraint u {unique {up[4:6], s, down[6:4], up[7]};}
endclass

class Inline;
  rand val_t x;
  rand val_t arr[5];
endclass

module t;
  initial begin
    automatic Lrm lrm = new;
    automatic LrmFits fits = new;
    automatic LrmCollides collides = new;
    automatic Slices sl = new;
    automatic Inline il = new;
    int ok;

    for (int n = 0; n < 10; ++n) begin
      ok = lrm.randomize();
      `checkd(ok, 1);
      `checkd(lrm.excluded, 5);
      Check#(byte)::distinct({lrm.b, lrm.a[2:3], lrm.excluded}, `__LINE__);

      ok = fits.randomize();
      `checkd(ok, 1);
      Check#(byte)::distinct({fits.b, fits.a[2:3], fits.excluded}, `__LINE__);
      `checkd(fits.b + fits.a[2] + fits.a[3], 3 + 4 + 6);

      ok = sl.randomize();
      `checkd(ok, 1);
      Check#()::distinct({sl.s, sl.up[4:7], sl.down[6:4]}, `__LINE__);

      ok = il.randomize() with {unique {il.arr[0:2], x, il.arr[4]};};
      `checkd(ok, 1);
      Check#()::distinct({il.x, il.arr[0:2], il.arr[4]}, `__LINE__);
    end

    // Three members cannot be distinct with two values left
    ok = collides.randomize();
    `checkd(ok, 0);

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
