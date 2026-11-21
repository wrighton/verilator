// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2019 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

typedef class Cls;

class Cls;
  integer imembera;
  integer imemberb;
endclass : Cls

module t;

  initial begin
    string a [*];
    string k;
    string v;

    Cls x;

    v = a.num("badarg");
    v = a.size("badarg");
    v = a.exists();  // Bad
    v = a.exists(k, "bad2");
    a.delete(k, "bad2");

    a.sort;  // Not legal on assoc
    a.rsort;  // Not legal on assoc
    a.reverse;  // Not legal on assoc
    a.shuffle;  // Not legal on assoc

    a.first;  // Not legal on wildcard
    a.last;  // Not legal on wildcard
    a.next;  // Not legal on wildcard
    a.prev;  // Not legal on wildcard
    a.unique_index;  // Not legal on wildcard
    a.find_index;  // Not legal on wildcard
    a.find_first_index;  // Not legal on wildcard
    a.find_last_index;  // Not legal on wildcard

    a[x] = "bad";

    a.bad_not_defined();
  end

  // Index-returning methods are illegal even when used as expressions
  // (IEEE 1800-2023 7.8.1, 7.9.4-7.9.7). Report each error without an internal error.
  class C;
    int mm[*];
    function void walk();
      int id;
      if (mm.first(id)) begin
        do begin
          mm[id] = 0;
        end while (mm.next(id));
      end
    endfunction
  endclass

  initial begin
    C c;
    c = new;
    c.walk();
  end

  typedef int wildcard_t[*];
  initial begin
    wildcard_t mm;
    int id;
    if (mm.last(id)) begin
      do begin
        mm[id] = 0;
      end while (mm.prev(id));
    end
  end
endmodule
