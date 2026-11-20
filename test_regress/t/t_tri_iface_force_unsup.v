// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Force values that may be z in a way not tracked, from the force value matrix of
// t_tri_iface_force_matrix, plus values of unknown z-ness.

// An always driven (weak plus a strong driver) or floating interface strength net
interface tgt_if #(
    parameter bit FLOATING = 0
) (
    input bit drv_on
);
  wire [1:0] value;
  if (FLOATING) begin : g_floating
    assign (weak0, weak1) value = drv_on ? 2'b00 : 2'bzz;
  end else begin : g_always
    assign (weak0, weak1) value = 2'b10;
    assign value = drv_on ? 2'b01 : 2'bzz;
  end
endinterface

module const_drv (
    output wire [1:0] o
);
  assign o = 2'b10;
endmodule

interface src_if;
  logic [1:0] l4 = 2'b11;
  bit [1:0] b2 = 2'b11;
  wire [1:0] w4 = l4;
  bit ten = 1'b0;
  wire [1:0] wt;
  assign (weak0, weak1) wt = ten ? 2'b10 : 2'bzz;
endinterface

module u_partial_net;
  tgt_if tgt (1'b0);
  bit s = 1'b1;
  wire [1:0] r;
  assign r[0] = s;
  task force_value;
    force tgt.value = r;
  endtask
  initial begin
    force tgt.value = r;
  end
endmodule

module u_undriven_net;
  tgt_if tgt (1'b0);
  wire [1:0] r;
  task force_value;
    force tgt.value = r;
  endtask
  initial begin
    force tgt.value = r;
  end
endmodule

module u_const_z;
  tgt_if tgt (1'b0);
  task force_value;
    force tgt.value = 2'bz1;
  endtask
endmodule

module u_tristate_concat;
  tgt_if tgt (1'b0);
  bit ten = 1'b0;
  wire [1:0] r;
  assign r = ten ? 2'b11 : 2'bzz;
  task force_value;
    force tgt.value = {r[0], 1'b1};
  endtask
  initial begin
    force tgt.value = {r[0], 1'b1};
  end
endmodule

module u_func_call;
  tgt_if tgt (1'b0);
  bit d = 1'b0;
  function automatic logic [1:0] fz(input bit x);
  return x ? 2'b01 : 2'bz1;
  endfunction
  task force_value;
    force tgt.value = fz(d);
  endtask
  initial begin
    force tgt.value = fz(d);
  end
endmodule

module u_tristate_cond;
  tgt_if tgt (1'b0);
  bit ten = 1'b0;
  bit c = 1'b1;
  wire [1:0] r;
  assign r = ten ? 2'b11 : 2'bzz;
  task force_value;
    force tgt.value = c ? r : 2'b01;
  endtask
  initial begin
    force tgt.value = c ? r : 2'b01;
  end
endmodule

module u_bitpull_net;
  tgt_if tgt (1'b0);
  bit ten = 1'b0;
  wire [1:0] r;
  assign r = ten ? 2'b11 : 2'bzz;
  pullup (r[0]);
  task force_value;
    force tgt.value = r;
  endtask
  initial begin
    force tgt.value = r;
  end
endmodule

module u_cell_const_net;
  tgt_if tgt (1'b0);
  wire [1:0] r;
  const_drv c (r);
  task force_value;
    force tgt.value = r;
  endtask
  initial begin
    force tgt.value = r;
  end
endmodule

module u_ports (
    tgt_if p,
    inout wire [1:0] io,
    input wire [1:0] in
);
  initial begin
    force p.value = io;
    force p.value = in;
  end
endmodule

module u_class_queue;
  tgt_if tgt (1'b0);
  class holder;
    logic [1:0] field;
  endclass
  holder held = new;
  logic [1:0] queued[$];
  initial begin
    force tgt.value = held.field;
    force tgt.value = queued[0];
  end
endmodule

module t;
  u_partial_net partial_net ();
  u_undriven_net undriven_net ();
  u_const_z const_z ();
  u_tristate_concat tristate_concat ();
  u_func_call func_call ();
  u_tristate_cond tristate_cond ();
  u_bitpull_net bitpull_net ();
  u_cell_const_net cell_const_net ();
  u_class_queue class_queue ();
  tgt_if port_tgt (1'b0);
  wire [1:0] port_io;
  assign port_io = 2'bzz;
  wire [1:0] port_in;
  u_ports ports (
      port_tgt,
      port_io,
      port_in
  );
endmodule
