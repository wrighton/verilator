// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

`timescale 1ns / 1ps

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got='h%x exp='h%x\n", `__FILE__, `__LINE__, (gotv), (expv)); `stop; end while (0);
// verilog_format: on

module rhs_source;
  bit enabled = 1;
  logic [6:0] value = 0;
  bit [6:0] plain_value = 0;
  wire [6:0] plain = plain_value;
  wire [8:2] q;
  assign q = enabled ? value : 7'bz;
endmodule

module replacing_forcer;
  function automatic logic [6:0] known_value(input bit select);
    bit [6:0] result;
    result = select ? 7'h5a : 7'h00;
    return result;
  endfunction
  initial begin
    #2;
    force t.n = t.source.q;
    force t.plain = t.source.plain;
    force t.fn = known_value(t.select);
    force t.slice = t.source.q[7:3];
  end
endmodule

module t;
  bit enabled = 1, select = 0;
  wire [6:0] n, fn, plain;
  wire [4:0] slice;
  assign n = enabled ? 7'h11 : 7'bz;
  assign plain = enabled ? 7'h11 : 7'bz;
  assign fn = enabled ? 7'h11 : 7'bz;
  assign slice = enabled ? 5'h11 : 5'bz;
  rhs_source source ();
  replacing_forcer forcer ();
  initial begin
    #1;
    force n = 7'bz;
    force plain = 7'bz;
    force fn = 7'bz;
    force slice = 5'bz;
    #2;
    `checkh(n, 7'h00);
    `checkh(n === 7'bz, 1'b0);
    `checkh(plain, 7'h00);
    `checkh(plain === 7'bz, 1'b0);
    `checkh(fn, 7'h00);
    `checkh(fn === 7'bz, 1'b0);
    `checkh(slice, 5'h00);
    `checkh(slice === 5'bz, 1'b0);
    select = 1;
    #1;
    `checkh(fn, 7'h5a);
    `checkh(fn === 7'bz, 1'b0);
    enabled = 0;
    source.enabled = 0;
    #1;
    `checkh(n === 7'bz, 1'b1);
    `checkh(slice === 5'bz, 1'b1);
    source.enabled = 1;
    source.value = 7'h5a;
    source.plain_value = 7'h35;
    #1;
    `checkh(n, 7'h5a);
    `checkh(plain, 7'h35);
    `checkh(plain === 7'bz, 1'b0);
    `checkh(n === 7'bz, 1'b0);
    `checkh(slice, 5'h0d);
    `checkh(slice === 5'bz, 1'b0);
    release n;
    release plain;
    release fn;
    release slice;
    #1;
    `checkh(n === 7'bz, 1'b1);
    `checkh(plain === 7'bz, 1'b1);
    `checkh(fn === 7'bz, 1'b1);
    `checkh(slice === 5'bz, 1'b1);
    enabled = 1;
    #1;
    `checkh(n, 7'h11);
    `checkh(plain, 7'h11);
    `checkh(fn, 7'h11);
    `checkh(slice, 5'h11);
    $write("*-* All Finished *-*\n");
    $finish;
  end

  // A runtime index selects the drive state of one source bit.
  logic [6:0] index_data = 7'b1010011, index_oe = 7'b0110101;
  wire [6:0] index_source;
  for (genvar b = 0; b < 7; ++b) begin : g_index_source
    assign index_source[b] = index_oe[b] ? index_data[b] : 1'bz;
  end
  bit index_target_en = 1;
  wire index_target;
  assign index_target = index_target_en ? 1'b1 : 1'bz;
  int index = 0;
  initial begin
    #1;
    force index_target = index_source[index];
    #0.1;
    `checkh(index_target, 1'b1);
    index = 1;
    #0.1;
    `checkh(index_target === 1'bz, 1'b1);
    index = 2;
    #0.1;
    `checkh(index_target, 1'b0);
    `checkh(index_target === 1'bz, 1'b0);
    index = 3;
    #0.1;
    `checkh(index_target === 1'bz, 1'b1);
    index_oe[3] = 1;
    #0.1;
    `checkh(index_target, 1'b0);
    `checkh(index_target === 1'bz, 1'b0);
    index_data[3] = 1;
    #0.1;
    `checkh(index_target, 1'b1);
    index = 6;
    #0.1;
    `checkh(index_target === 1'bz, 1'b1);
    // An out of range bit reads as x, which the force drives (IEEE 1800-2023 11.5.1).
    index = 9;
    #0.1;
    `checkh(index_target === 1'bz, 1'b0);
    index = -1;
    #0.1;
    `checkh(index_target === 1'bz, 1'b0);
    release index_target;
    #0.1;
    `checkh(index_target, 1'b1);
    `checkh(index_target === 1'bz, 1'b0);
  end

  // A deterministic function index selects the same bit for its value and drive state.
  function automatic int mirrored_index(int position);
    int result;
    result = 6 - position;
    return result;
  endfunction
  wire function_target;
  assign function_target = index_target_en ? 1'b1 : 1'bz;
  int function_index = 6;
  initial begin
    #1;
    force function_target = index_source[mirrored_index(function_index)];
    #0.1;
    `checkh(function_target, 1'b1);
    `checkh(function_target === 1'bz, 1'b0);
    function_index = 5;
    force function_target = index_source[mirrored_index(function_index)];
    #0.1;
    `checkh(function_target === 1'bz, 1'b1);
    function_index = 4;
    force function_target = index_source[mirrored_index(function_index)];
    #0.1;
    `checkh(function_target, 1'b0);
    `checkh(function_target === 1'bz, 1'b0);
    release function_target;
    #0.1;
    `checkh(function_target, 1'b1);
  end

  // A part select partly out of range drives its out of range bits.
  wire [1:0] part_target;
  assign part_target = index_target_en ? 2'b11 : 2'bzz;
  int part_index = 0;
  initial begin
    #1;
    force part_target = index_source[part_index+:2];
    #0.1;
    `checkh(part_target[1] === 1'bz, 1'b1);
    `checkh(part_target[0], 1'b1);
    part_index = 5;
    #0.1;
    `checkh(part_target[1] === 1'bz, 1'b1);
    `checkh(part_target[0], 1'b0);
    part_index = 6;
    #0.1;
    `checkh(part_target[1] === 1'bz, 1'b0);
    `checkh(part_target[0] === 1'bz, 1'b1);
    part_index = -1;
    #0.1;
    `checkh(part_target[1], 1'b1);
    `checkh(part_target[0] === 1'bz, 1'b0);
    part_index = 7;
    #0.1;
    `checkh(part_target === 2'bzz, 1'b0);
    `checkh(part_target[1] === 1'bz, 1'b0);
    `checkh(part_target[0] === 1'bz, 1'b0);
    release part_target;
    #0.1;
    `checkh(part_target, 2'b11);
  end
endmodule
