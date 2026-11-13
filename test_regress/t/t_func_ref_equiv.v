// DESCRIPTION: Verilator: Verilog Test module
//
// A ref argument accepts an equivalent packed type: the same total width,
// both 2-state or 4-state, and the same signedness (IEEE 1800-2023 6.22.2 c).
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

  int cyc = 0;
  always @(posedge clk) begin
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
    if (cyc == 5) begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
