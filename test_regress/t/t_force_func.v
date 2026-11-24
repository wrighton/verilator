// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2025 Antmicro
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0)
// verilog_format: on

function bit [1:0] get_arg(bit [1:0] x);
  return x;
endfunction

module t;
  bit [1:0] a;
  bit [1:0] b = 1;

  function automatic logic [6:0] mix(logic [6:0] value);
    return value ^ 7'h5a;
  endfunction

  function automatic int mirrored_index(int position);
    int result = 6 - position;
    return result;
  endfunction

  class Transformer;
    function logic [6:0] next_value(logic [6:0] value);
      return value + 7'd1;
    endfunction
  endclass

  logic [6:0] data = 7'b1010011;
  int position = 6;
  logic [6:0] arg = 7'd17;
  logic [6:0] offset = 7'd2;
  logic [6:0] driver = 7'd23;
  wire [6:0] net_target = driver;
  logic bit_target;
  logic [6:0] method_target;
  Transformer transformer;

  int samples = 0;
  function automatic logic [6:0] sample ();
    ++samples;
    return 7'd4;
  endfunction
  logic [6:0] sampled_target;

  initial begin
    // IEEE 1800-2023 10.6: force a = b + f(c) follows changes to both b and c.
    #1;
    arg = 0;
    force net_target = offset + mix(arg);
    `checkh(net_target, 7'h5c);
    force bit_target = data[mirrored_index(position)];
    transformer = new;
    force method_target = transformer.next_value(mix(arg));
    force sampled_target = offset + sample ();
    `checkh(samples, 1);
    #1;
    `checkh(bit_target, 1'b1);
    `checkh(method_target, 7'h5b);
    `checkh(sampled_target, 7'd6);

    arg = 1;
    position = 4;
    #1;
    `checkh(net_target, 7'h5d);
    `checkh(bit_target, 1'b0);
    `checkh(method_target, 7'h5c);

    arg = 7'h55;
    offset = 7'd8;
    driver = 7'd41;
    #1;
    `checkh(net_target, 7'h17);
    `checkh(method_target, 7'h10);
    `checkh(sampled_target, 7'd12);
    `checkh(samples, 1);

    // Replacing a slice leaves the rest of the first force live.
    force net_target[3:2] = 2'b00;
    arg = 0;
    #1;
    `checkh(net_target, 7'h62);
    `checkh(method_target, 7'h5b);

    // IEEE 1800-2023 10.6.2: release restores a net driver and holds a variable.
    release net_target;
    release bit_target;
    release method_target;
    transformer = null;
    release sampled_target;
    arg = 0;
    offset = 0;
    position = 6;
    driver = 7'd42;
    #1;
    `checkh(net_target, 7'd42);
    `checkh(bit_target, 1'b0);
    `checkh(method_target, 7'h5b);
    `checkh(sampled_target, 7'd12);
    `checkh(samples, 1);

    #1 a = 0;
    force b = get_arg(a);
    `checkh(a, 0);
    `checkh(b, 0);

    a = 1;
    #1;
    `checkh(a, 1);
    `checkh(b, 1);

    a = 2;
    #1;
    `checkh(a, 2);
    `checkh(b, 2);

    a = 3;
    #1;
    `checkh(a, 3);
    `checkh(b, 3);

    release b;
    `checkh(a, 3);
    `checkh(b, 3);

    b = 2;
    `checkh(b, 2);

    #1 $finish;
  end

endmodule
