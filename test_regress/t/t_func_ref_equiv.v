// DESCRIPTION: Verilator: Verilog Test module
//
// A ref argument accepts an equivalent packed type: the same total width,
// both 2-state or 4-state, and the same signedness (IEEE 1800-2023 6.22.2 c),
// and an unpacked array of equivalent elements (IEEE 1800-2023 6.22.2 d, e).
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module t (
    input clk
);
  typedef struct packed {
    logic [3:0] id;
    logic [7:0] data;
  } a_t;
  typedef struct packed {
    logic [1:0] hi;
    logic [1:0] lo;
    logic [7:0] data;
  } b_t;
  typedef struct packed {
    logic [32:0] x;
    logic [31:0] y;
  } w_t;  // 65 bits
  typedef union packed {
    logic [64:0] v;
    w_t w;
  } wu_t;
  typedef struct packed {bit [6:0] a;} s7_t;
  typedef logic [3:0][2:0] pa_t;

  function automatic void set_data(ref a_t a, input logic [7:0] d);
    a.data = d;
  endfunction
  task automatic set_x(ref w_t w, input logic [32:0] x);
    // verilator no_inline_task
    w.x = x;
  endtask
  function automatic int add_one(const ref int i);
    return i + 1;
  endfunction
  function automatic void set_top(ref pa_t p, input logic [2:0] v);
    // verilator no_inline_task
    p[3] = v;
  endfunction
  function automatic void set_s7(ref s7_t s, input bit [6:0] v);
    s.a = v;
  endfunction

  function automatic void set_vec(ref logic [11:0] v, input logic [7:0] d);
    // verilator no_inline_task
    v[7:0] = d;
  endfunction
  function automatic void set_vec_inl(ref logic [11:0] v, input logic [3:0] d);
    v[11:8] = d;
  endfunction

  function automatic void set_dyn(ref byte unsigned p[], input byte unsigned v);
    p[1] = v;
  endfunction
  task automatic push_q(ref bit signed [7:0] p[$], input bit signed [7:0] v);
    // verilator no_inline_task
    p.push_back(v);
  endtask
  function automatic void set_assoc(ref a_t p[int], input int k, input logic [7:0] d);
    p[k].data = d;
  endfunction
  function automatic void set_wild(ref byte unsigned p[*], input byte unsigned v);
    p[3] = v;
  endfunction
  function automatic void set_fixed(ref s7_t p[2:0], input bit [6:0] v);
    p[1].a = v;
  endfunction
  function automatic void set_bounded(ref pa_t p[$:2], input logic [2:0] v);
    // verilator no_inline_task
    p[0][1] = v;
  endfunction
  function automatic void set_nested(ref byte unsigned p[1:0][], input byte unsigned v);
    p[0] = new[2];
    p[0][1] = v;
  endfunction

  int cyc = 0;
  always @(posedge clk) begin
    bit [7:0] dyn[];
    byte que[$];
    logic [11:0] assoc[bit signed [31:0]];
    bit [7:0] wild[*];
    bit [6:0] fixed[2:0];
    bit [7:0] nested[1:0][];
    logic [11:0] bounded[$:2];
    b_t b;
    logic [11:0] v12;
    logic [11:0] v12b;
    pa_t pa;
    wu_t wu;
    logic [64:0] v65;
    bit signed [31:0] si;
    bit [6:0] b7;
    cyc <= cyc + 1;
    b = '0;
    v12 = '1;
    v12b = '0;
    pa = '0;
    wu = '0;
    v65 = '0;
    si = 40 + cyc;
    b7 = '0;
    set_data(b, 8'h50 + 8'(cyc));  // Struct to struct
    set_data(v12, 8'h60 + 8'(cyc));  // Vector to struct
    set_x(wu, {1'b1, 32'(cyc)});  // Union to struct, wide
    set_x(v65, {1'b1, 32'(cyc)});
    set_top(v12b, 3'(cyc));  // Vector to packed array
    set_s7(b7, 7'h10 + 7'(cyc));  // 2-state
    `checkh(b.data, 8'h50 + 8'(cyc));
    `checkh(b.hi, 2'h0);
    `checkh(v12, {4'hf, 8'h60 + 8'(cyc)});
    `checkh(wu.w.x, {1'b1, 32'(cyc)});
    `checkh(v65, {1'b1, 32'(cyc), 32'h0});
    `checkd(add_one(si), 41 + cyc);  // Signed vector to int
    `checkh(v12b, {3'(cyc), 9'h0});
    `checkh(b7, 7'h10 + 7'(cyc));
    set_vec(b, 8'h70 + 8'(cyc));  // Struct to vector
    set_vec_inl(b, 4'(cyc));
    set_vec(pa, 8'h80 + 8'(cyc));  // Packed array to vector
    set_vec_inl(pa, 4'(cyc));
    `checkh(b, {4'(cyc), 8'h70 + 8'(cyc)});
    `checkh(pa, {4'(cyc), 8'h80 + 8'(cyc)});
    dyn = new[2];
    que = '{8'sh7f};
    assoc[-1] = 12'h5ff;
    fixed = '{default: '0};
    set_dyn(dyn, 8'h90 + 8'(cyc));  // Dynamic array of vectors to one of byte unsigned
    push_q(que, -8'(cyc));  // Queue of byte to one of signed vectors
    set_assoc(assoc, -1, 8'ha0 + 8'(cyc));  // Equivalent index and element types
    set_wild(wild, 8'hb0 + 8'(cyc));
    set_fixed(fixed, 7'h30 + 7'(cyc));  // Fixed-size array of vectors to one of structures
    set_nested(nested, 8'hc0 + 8'(cyc));  // Fixed-size array of dynamic arrays
    bounded = '{12'h0};
    set_bounded(bounded, 3'(cyc));  // Queues of the same bound
    `checkh(dyn[1], 8'h90 + 8'(cyc));
    `checkd(que.size(), 2);
    `checkh(que[1], -8'(cyc));
    `checkh(assoc[-1], {4'h5, 8'ha0 + 8'(cyc)});
    `checkh(wild[3], 8'hb0 + 8'(cyc));
    `checkh(fixed[1], 7'h30 + 7'(cyc));
    `checkh(fixed[0], 7'h0);
    `checkh(nested[0][1], 8'hc0 + 8'(cyc));
    `checkh(bounded[0], {9'h0, 3'(cyc)} << 3);
    if (cyc == 5) begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
