// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Antmicro
// SPDX-License-Identifier: CC0-1.0

task dyn_task(input logic [30:0] data[]);
  $display("%p", data);
endtask

task unpacked_task(input logic [30:0] data[3:0]);
  $display("%p", data);
endtask

task queue_task(input logic [30:0] data[$]);
  $display("%p", data);
endtask

task assoc_task(input logic [30:0] data[int]);
  $display("%p", data);
endtask

task scalar_task(input logic data);
  $display("%b", data);
endtask

task scalar_vec_task(input logic [30:0] data);
  $display("%b", data);
endtask

typedef struct {logic [30:0] data;} ustruct_t;

task ustruct_task(input ustruct_t data);
  $display("%p", data);
endtask

function logic logical_or(input logic a, b);
  return a | b;
endfunction

module t;
  logic unpacked_data[3:0];
  logic dyn_data[];
  logic queue_data[$];
  logic assoc_data[int];
  logic vec_data[3:0];
  logic [30:0] wildcard_data[*];
  ustruct_t ustruct_data;
  logic my_signal_a[10];
  logic my_signal_b[10];
  string str = "ab";
  localparam string STR = "ab";
  initial begin
    dyn_task(.data($urandom));
    unpacked_task(.data($urandom));
    queue_task(.data($urandom));
    assoc_task(.data($urandom));
    scalar_task(.data(unpacked_data));
    scalar_task(.data(dyn_data));
    scalar_task(.data(queue_data));
    scalar_task(.data(assoc_data));
    scalar_vec_task(.data(vec_data));
    scalar_vec_task(.data(wildcard_data));
    scalar_vec_task(.data(ustruct_data));
    ustruct_task(.data(1));
    logical_or(my_signal_a[0], my_signal_b);
    unpacked_task(.data("ab"));
    dyn_task(.data("ab"));
    bytes_ref_task("ab");
    bytes_const_ref_task("ab");
    bytes_output_task("ab");
    bytes_input_task(16'h6162);
    bytes_input_task(str);
    bytes_input_task(STR);
    bytes_input_task($typename(str));
    bytes2_input_task("ab");
    $write("*-* All Finished *-*\n");
    $finish;
  end

  // A string literal is converted only by value to an unpacked array of bytes
  task automatic bytes_ref_task(ref byte data[1:0]);
  endtask
  task automatic bytes_const_ref_task(const ref byte data[1:0]);
  endtask
  task bytes_output_task(output byte data[1:0]);
  endtask
  task bytes_input_task(input byte data[1:0]);
  endtask
  task bytes2_input_task(input byte data[1:0][1:0]);
  endtask
endmodule
