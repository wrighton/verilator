// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Function call results cannot be passed by reference (IEEE 1800-2023 13.5.2)

package pkg;
  function automatic int get_p();
    return 1;
  endfunction
endpackage

class Cls;
  int m_q[$];
  function int get_m();
    return 2;
  endfunction
  static function int get_s();
    return 3;
  endfunction
  function void set(ref int r);
    r = 4;
  endfunction
endclass

module t;
  typedef byte unsigned bytes_t[$];
  typedef int ints_t[$];

  function automatic int get_i();
    return 5;
  endfunction
  function automatic bytes_t get_q();
    return '{8'h1, 8'h2};
  endfunction
  function automatic ints_t get_ints();
    return '{7, 8};
  endfunction
  function automatic string get_str();
    return "a";
  endfunction
  function automatic void set(ref int r);
    r = 6;
  endfunction
  function automatic void set_str(ref string s);
    s = "b";
  endfunction
  function automatic int size(const ref byte unsigned b[$]);
    return b.size();
  endfunction

  initial begin
    Cls c;
    bytes_t b;
    int i;
    c = new;
    set(get_i());  // BAD
    set(pkg::get_p());  // BAD
    set(Cls::get_s());  // BAD
    set(c.get_m());  // BAD
    set(c.m_q.pop_front());  // BAD
    c.set(get_i());  // BAD
    i = size(get_q());  // BAD: const ref
    set(get_ints()[0]);  // BAD: element of a call result
    set_str(get_str());  // BAD: string
    // Legal
    set(i);
    c.set(c.m_q[0]);
    i = size(b);
  end
endmodule
