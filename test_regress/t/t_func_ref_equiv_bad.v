// DESCRIPTION: Verilator: Verilog Test module
//
// A ref argument rejects a type not equivalent (IEEE 1800-2023 6.22.2, 13.5.2).
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;
  typedef struct packed {
    logic [3:0] id;
    logic [7:0] data;
  } a_t;
  typedef struct packed {
    bit [3:0] id;
    bit [7:0] data;
  } a2_t;
  typedef struct packed signed {
    logic [3:0] id;
    logic [7:0] data;
  } as_t;
  typedef struct {
    logic [3:0] id;
    logic [7:0] data;
  } u_t;
  typedef struct {
    logic [3:0] id;
    logic [7:0] data;
  } u2_t;
  typedef enum logic [11:0] {E0} e_t;
  typedef a_t [1:0] aa_t;

  function automatic void f(ref a_t a);
  endfunction
  function automatic void fu(ref u_t a);
  endfunction
  function automatic void faa(ref aa_t a);
  endfunction
  function automatic void fi(ref int a);
  endfunction
  function automatic void fc(ref chandle a);
  endfunction
  function automatic void fd(ref byte unsigned a[]);
  endfunction
  function automatic void ff(ref byte unsigned a[2:0]);
  endfunction
  function automatic void fa(ref byte unsigned a[int]);
  endfunction
  function automatic void fl(ref logic [11:0] a[]);
  endfunction

  initial begin
    logic [12:0] v13;
    a2_t a2;
    as_t as;
    u2_t u2;
    e_t e;
    bit [23:0] b24;
    logic [31:0] l32;
    // verilator lint_off WIDTH
    f(v13);  // Different width
    // verilator lint_on WIDTH
    f(a2);  // 2-state
    f(as);  // Signed
    fu(u2);  // Unpacked structure
    f(e);  // Enum
    faa(b24);  // 2-state, to a packed array of 4-state structures
    fi(l32);  // 4-state
    fc(l32);  // Not integral
    begin
      byte unsigned q[$];
      logic [7:0] l8[];
      e_t ea[];
      byte unsigned f4[3:0];
      byte unsigned au[bit [31:0]];
      fd(q);  // Queue to a dynamic array
      fd(l8);  // 4-state elements
      ff(f4);  // Different size
      fa(au);  // Unsigned index
      fl(ea);  // Enum elements
    end
  end
endmodule
