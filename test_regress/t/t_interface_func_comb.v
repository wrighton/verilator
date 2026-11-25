// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0)
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0)
// verilog_format: on

interface ifc;
  logic [6:0] q;
  logic [14:0] w;
  int data = 0;

  function automatic logic [6:0] peek();
    // verilator no_inline_task
    return q;
  endfunction

  function automatic logic [14:0] peek_sum(input logic [6:0] d);
    logic [14:0] sum;
    sum = w + 15'(d);
    return sum;
  endfunction

  function logic [6:0] peek_nested();
    return peek() ^ 7'h55;
  endfunction

  function automatic void get_func(output int result);
    // verilator no_inline_task
    result = data;
  endfunction

  task automatic get_task(output int result);
    // verilator no_inline_task
    result = data;
  endtask
endinterface

class Counter;
  static int calls = 0;
  static logic [6:0] sv = 0;
  static function int count();
    ++calls;
    return calls;
  endfunction
  static function logic [6:0] get_sv();
    // verilator no_inline_task
    return sv;
  endfunction
endclass

module t (
    input clk
);
  int cyc = 0;
  logic [63:0] crc = 64'h5aef0c8d_d70a4497;

  ifc i ();

  always @(posedge clk) begin
    cyc <= cyc + 1;
    crc <= {crc[62:0], crc[63] ^ crc[2] ^ crc[0]};
    i.q <= crc[6:0];
    i.w <= crc[30:16];
    i.data <= cyc + 1;
  end

  // An always_comb is sensitive to the variables read by the functions it
  // calls (IEEE 1800-2023 9.2.2.2.1)
  logic [6:0] peeked;
  always_comb peeked = i.peek();

  logic [6:0] slow = 0;
  always @(posedge clk) if (cyc[2:0] == 0) slow <= slow + 7'd1;
  logic [14:0] summed;
  always_comb summed = i.peek_sum(slow);

  logic [6:0] nested;
  always_comb nested = i.peek_nested();

  int funced;
  always_comb i.get_func(funced);

  // The body of a task called by an always_comb does not add to its sensitivity,
  // so this is evaluated only at time zero
  int tasked;
  always_comb i.get_task(tasked);

  // Also for static class methods
  always @(posedge clk) Counter::sv <= crc[54:48];
  logic [6:0] got_sv;
  always_comb got_sv = Counter::get_sv();

  // A continuous assignment with constant operands is evaluated once, even
  // though the function it calls changes a variable it reads
  int counted;
  assign counted = Counter::count();

  always @(posedge clk) begin
    if (cyc > 1) begin
      `checkh(peeked, i.q);
      `checkh(summed, i.w + 15'(slow));
      `checkh(nested, i.q ^ 7'h55);
      `checkd(funced, i.data);
      `checkh(got_sv, Counter::sv);
      `checkd(tasked, 0);
    end
    if (cyc == 99) begin
      `checkd(counted, 1);
      `checkd(Counter::calls, 1);
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
