// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// Sequences and properties instanced by a hierarchical name (IEEE 1800-2023 16.8, 16.12)

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

package pkg;
  logic en = 1;
endpackage

interface ifc (
    input logic clk
);
  logic v = 0;
  logic r = 0;
  property p_hold;
    v && !r |=> v;
  endproperty
  sequence s_hs;
    v ##1 r;
  endsequence
  sequence s_nested;
    s_hs;
  endsequence
  sequence s_v;
    v;
  endsequence
  property p_clk;
    @(posedge clk) r |=> !r;
  endproperty
  property p_arg(x);
    v && pkg::en |-> x;
  endproperty
  function automatic bit f_both();
    return v && r;
  endfunction
  property p_func;
    f_both() |=> !v;
  endproperty
  property p_nested;
    s_v;
  endproperty
endinterface

module sub (
    input logic clk
);
  logic v = 0;
  property p_hold;
    v |=> !v;
  endproperty
  ifc u_in (clk);
  property p_in;
    u_in.v |=> u_in.f_both();
  endproperty
endmodule

module chk (
    ifc m
);
  int fails = 0;
  assert property (@(posedge m.clk) m.p_hold)
  else ++fails;
endmodule

module t;
  logic clk = 0;
  always #5 clk = ~clk;

  logic [63:0] crc = 64'h5aef0c8d_d70a4497;

  ifc u_if1 (clk);
  ifc u_if2 (clk);
  sub u_sub (clk);
  chk u_chk (u_if2);

  // Stimulus differs per instance, so each reference must see its own instance
  always @(posedge clk) begin
    crc <= {crc[62:0], crc[63] ^ crc[2] ^ crc[0]};
    u_if1.v <= crc[0];
    u_if1.r <= crc[1];
    u_if2.v <= crc[2];
    u_if2.r <= crc[3];
    u_sub.v <= crc[4];
    u_sub.u_in.v <= crc[6];
    u_sub.u_in.r <= crc[7];
  end

  // Each instance is compared against the equivalent expression written in this scope
  int fails_hold1 = 0;
  int fails_hold1_ref = 0;
  assert property (@(posedge clk) u_if1.p_hold)
  else ++fails_hold1;
  assert property (@(posedge clk) u_if1.v && !u_if1.r |=> u_if1.v)
  else ++fails_hold1_ref;

  int fails_hold2 = 0;
  int fails_hold2_ref = 0;
  assert property (@(posedge clk) u_if2.p_hold)
  else ++fails_hold2;
  assert property (@(posedge clk) u_if2.v && !u_if2.r |=> u_if2.v)
  else ++fails_hold2_ref;

  int hits_hs = 0;
  int hits_hs_ref = 0;
  cover property (@(posedge clk) u_if1.s_hs ##1 !u_if1.v) ++hits_hs;
  cover property (@(posedge clk) u_if1.v ##1 u_if1.r ##1 !u_if1.v) ++hits_hs_ref;

  int hits_nested = 0;
  int hits_nested_ref = 0;
  cover property (@(posedge clk) u_if2.s_nested) ++hits_nested;
  cover property (@(posedge clk) u_if2.v ##1 u_if2.r) ++hits_nested_ref;

  int hits_v = 0;
  cover property (@(posedge clk) u_if2.s_v ##1 u_if2.r) ++hits_v;

  int fails_clk = 0;
  int fails_clk_ref = 0;
  assert property (u_if1.p_clk)
  else ++fails_clk;
  assert property (@(posedge clk) u_if1.r |=> !u_if1.r)
  else ++fails_clk_ref;

  // The actual argument refers to this scope, not to the interface
  logic r = 0;
  always @(posedge clk) r <= crc[5];
  int fails_arg = 0;
  int fails_arg_ref = 0;
  assert property (@(posedge clk) u_if1.p_arg(r))
  else ++fails_arg;
  assert property (@(posedge clk) u_if1.v |-> r)
  else ++fails_arg_ref;

  int fails_func = 0;
  int fails_func_ref = 0;
  assert property (@(posedge clk) u_if1.p_func)
  else ++fails_func;
  assert property (@(posedge clk) u_if1.v && u_if1.r |=> !u_if1.v)
  else ++fails_func_ref;

  // A property instance nested in a property operator
  int fails_not = 0;
  int fails_not_ref = 0;
  assert property (@(posedge clk) not u_if1.p_nested)
  else ++fails_not;
  assert property (@(posedge clk) not u_if1.v)
  else ++fails_not_ref;

  int fails_sub = 0;
  int fails_sub_ref = 0;
  assert property (@(posedge clk) u_sub.p_hold)
  else ++fails_sub;
  assert property (@(posedge clk) u_sub.v |=> !u_sub.v)
  else ++fails_sub_ref;

  int fails_in = 0;
  int fails_in_ref = 0;
  assert property (@(posedge clk) u_sub.p_in)
  else ++fails_in;
  assert property (@(posedge clk) u_sub.u_in.v |=> u_sub.u_in.v && u_sub.u_in.r)
  else ++fails_in_ref;

  initial begin
    #400;
    `checkd(fails_hold1, 6);
    `checkd(fails_hold1_ref, 6);
    `checkd(fails_hold2, 6);
    `checkd(fails_hold2_ref, 6);
    `checkd(u_chk.fails, 6);
    `checkd(hits_hs, 10);
    `checkd(hits_hs_ref, 10);
    `checkd(hits_nested, 18);
    `checkd(hits_nested_ref, 18);
    `checkd(hits_v, 18);
    `checkd(fails_clk, 7);
    `checkd(fails_clk_ref, 7);
    `checkd(fails_arg, 11);
    `checkd(fails_arg_ref, 11);
    `checkd(fails_func, 2);
    `checkd(fails_func_ref, 2);
    `checkd(fails_not, 17);
    `checkd(fails_not_ref, 17);
    `checkd(fails_sub, 6);
    `checkd(fails_sub_ref, 6);
    `checkd(fails_in, 11);
    `checkd(fails_in_ref, 11);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
