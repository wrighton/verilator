// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define checks(gotv,expv) do if ((gotv) != (expv)) begin $write("%%Error: %s:%0d:  got='%s' exp='%s'\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// A model evaluated from within a process of another model does not draw from
// that process's RNG (IEEE 1800-2023 18.14.1)

class Rand;
  rand int unsigned m_val;
endclass

module a;
  import "DPI-C" context function void eval_b();
  import "DPI-C" function int b_objects();
  initial begin
    process p;
    string state;
    int unsigned drawnAfter;
    int unsigned drawnControl;
    p = process::self();
    #1 p.srandom(42);
    state = p.get_randstate();
    // Model b resumes a process, then creates an object without a process of its own
    eval_b();
    `checkh(b_objects(), 1);
    `checks(p.get_randstate(), state);
    // This process is current again
    drawnAfter = $urandom;
    p.srandom(42);
    drawnControl = $urandom;
    `checkh(drawnAfter, drawnControl);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule

module b;
  import "DPI-C" function void b_created();
  logic clk = 1'b0;
  Rand obj;
  int randomize_result;
  always @(posedge clk) begin
    obj = new;
    randomize_result = obj.randomize();
    b_created();
  end
  initial begin
    process p;
    p = process::self();
    #1 clk = 1'b1;
  end
endmodule
