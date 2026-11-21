// DESCRIPTION: Verilator: Test for self-referential interface typedef
//
// This program is free software; you can redistribute it and/or modify it
// under the terms of either the GNU Lesser General Public License Version 3
// or the Perl Artistic License Version 2.0.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: LGPL-3.0-only OR Artistic-2.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Self-referential typedef: typedef iface#(T) this_type inside interface iface
interface my_iface #(
    type T = logic
);
  typedef my_iface#(T) self_t;
  T data;
endinterface

// Value-parameterized interface with virtual interface types of itself and of another
// specialization of itself
interface val_iface #(
    parameter int W = 4
);
  typedef virtual val_iface #(W) self_t;
  typedef virtual val_iface #(8) other_t;
  logic [W-1:0] data;
  self_t self;
  other_t other;
  function automatic int sum(self_t o);
    return int'(o.data) + int'(self.data) + int'(other.data);
  endfunction
endinterface

typedef logic [5:0] six_t;

// Type- and value-parameterized interface with virtual interface types of itself and of
// another specialization of itself
interface mix_iface #(
    type T = logic,
    parameter int W = 4
);
  typedef virtual mix_iface #(T, W) self_t;
  typedef virtual mix_iface #(six_t, W) six_vif_t;
  T t;
  logic [W-1:0] data;
  self_t self;
  six_vif_t six;
endinterface

module t;
  my_iface #(logic [7:0]) if0 ();
  val_iface v4 ();
  val_iface #(5) v0 ();
  val_iface #(5) v1 ();
  val_iface #(8) v8 ();
  mix_iface #(logic [2:0], 5) m0 ();
  mix_iface #(logic [2:0], 5) m1 ();
  mix_iface #(six_t, 5) m6 ();

  initial begin
    if0.data = 8'hAB;
    if ($bits(if0.data) != 8) $stop;

    v0.self = v1;
    v0.other = v8;
    v8.self = v8;
    v8.other = v8;
    v0.data = 5'h11;
    v1.data = 5'h1e;
    v8.data = 8'h81;
    `checkd(v0.sum(v0), 'h11 + 'h1e + 'h81);
    `checkd(v8.sum(v8), 3 * 'h81);
    `checkd($bits(v0.self.data), 5);
    `checkd($bits(v0.other.data), 8);
    v4.self = v4;
    v4.other = v8;
    v4.data = 4'h9;
    `checkd(v4.sum(v4), 'h9 + 'h9 + 'h81);

    m0.self = m1;
    m0.six = m6;
    m1.t = 3'h5;
    m6.t = 6'h2a;
    m6.data = 5'h13;
    `checkd(m0.self.t, 3'h5);
    `checkd(m0.six.t, 6'h2a);
    `checkd(m0.six.data, 5'h13);
    `checkd($bits(m0.self.t), 3);
    `checkd($bits(m0.six.t), 6);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
