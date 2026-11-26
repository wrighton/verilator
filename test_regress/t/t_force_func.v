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

  int traced_calls = 0;
  function automatic logic [6:0] traced(logic [6:0] value);
    ++traced_calls;
    return value;
  endfunction
  logic [6:0] traced_direct;
  logic [6:0] traced_nested;

  class DrawBase;
    virtual function int value(int x);
      return x;
    endfunction
  endclass

  class DrawOverride extends DrawBase;
    function int value(int x);
      return x ^ $urandom;
    endfunction
  endclass

  function automatic int wrapped_draw(int x);
    return x ^ $urandom;
  endfunction

  function automatic int draw(int x);
    return wrapped_draw(x);
  endfunction

  int plain_random;
  int hidden_random;
  int virtual_random;
  DrawBase random_source;
  DrawOverride random_override = new;

  initial begin
    // None of these force-site samples may be repeated when the scheduler settles.
    random_source = random_override;
    repeat (4) begin
      logic [95:0] sampled;
      #1;
      force plain_random = int'(mix(arg)) ^ $urandom;
      force hidden_random = draw(int'(arg));
      force virtual_random = random_source.value(int'(arg));
      sampled = {plain_random, hidden_random, virtual_random};
      #1;
      `checkh({plain_random, hidden_random, virtual_random}, sampled);
      arg ^= 7'd1;
      #1;
      `checkh(plain_random == sampled[95:64], 1'b0);
      `checkh(hidden_random == sampled[63:32], 1'b0);
      `checkh(virtual_random == sampled[31:0], 1'b0);
      release plain_random;
      release hidden_random;
      release virtual_random;
    end
    // IEEE 1800-2023 10.6: force a = b + f(c) follows changes to both b and c.
    #1;
    arg = 0;
    force net_target = offset + mix(arg);
    `checkh(net_target, 7'h5c);
    force bit_target = data[mirrored_index(position)];
    transformer = new;
    force method_target = transformer.next_value(mix(arg));
    force sampled_target = sample ();
    `checkh(samples, 1);
    force traced_direct = traced(arg);
    force traced_nested = ~traced(arg);
    `checkh(traced_calls, 2);
    #1;
    `checkh(traced_calls, 2);
    `checkh(traced_direct, 7'd0);
    `checkh(traced_nested, 7'h7f);
    `checkh(bit_target, 1'b1);
    `checkh(method_target, 7'h5b);
    `checkh(sampled_target, 7'd4);

    arg = 1;
    position = 4;
    #1;
    `checkh(net_target, 7'h5d);
    `checkh(bit_target, 1'b0);
    `checkh(method_target, 7'h5c);
    `checkh(traced_calls, 4);
    `checkh(traced_direct, 7'd1);
    `checkh(traced_nested, 7'h7e);
    release traced_direct;
    release traced_nested;

    arg = 7'h55;
    offset = 7'd8;
    driver = 7'd41;
    #1;
    `checkh(net_target, 7'h17);
    `checkh(method_target, 7'h10);
    `checkh(sampled_target, 7'd4);
    `checkh(samples, 1);
    `checkh(traced_calls, 4);

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
    `checkh(sampled_target, 7'd4);
    `checkh(samples, 1);
    `checkh(traced_calls, 4);

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

  // A force of a concatenation follows its value while any of its parts is forced
  int concat_calls = 0;
  logic [1:0] concat_arg = 2'b01;
  function automatic logic [1:0] concat_value(logic [1:0] value);
    ++concat_calls;
    return value;
  endfunction
  wire [3:0] concat_net = '0;
  initial begin
    #1;
    force {concat_net[3], concat_net[0]} = concat_value(concat_arg);
    `checkh(concat_calls, 1);
    #1;
    `checkh(concat_net, 4'h1);
    concat_arg = 2'b10;
    #1;
    `checkh(concat_net, 4'h8);
    `checkh(concat_calls, 2);
    release concat_net[3];
    concat_arg = 2'b01;
    #1;
    `checkh(concat_net, 4'h1);
    `checkh(concat_calls, 3);
    release concat_net[0];
    concat_arg = 2'b11;
    #1;
    `checkh(concat_net, 4'h0);
    `checkh(concat_calls, 3);
  end

  // A force in a task follows its value only from the call that executed it
  int task_calls = 0;
  logic [1:0] task_arg = 2'b01;
  function automatic logic [1:0] task_value(logic [1:0] value);
    ++task_calls;
    return value;
  endfunction
  wire [3:0] task_net = '0;
  bit task_never = 0;
  task automatic task_force();
    force {task_net[3], task_net[0]} = task_value(task_arg);
  endtask
  initial begin
    #1;
    task_force();
    `checkh(task_calls, 1);
    #1;
    task_arg = 2'b10;
    #1;
    `checkh(task_net, 4'h8);
    `checkh(task_calls, 2);
    release task_net;
    task_arg = 2'b11;
    #1;
    `checkh(task_net, 4'h0);
    `checkh(task_calls, 2);
  end
  initial begin
    #2;
    if (task_never) task_force();
  end

  // A force in a task called from two processes follows the value of the call owning the bits
  int shared_calls = 0;
  logic [1:0] shared_arg = 2'b01;
  function automatic logic [1:0] shared_value(logic [1:0] value);
    ++shared_calls;
    return value;
  endfunction
  wire [3:0] shared_net = '0;
  task automatic shared_force();
    force {shared_net[3], shared_net[0]} = shared_value(shared_arg);
  endtask
  initial begin
    #1;
    shared_force();
    `checkh(shared_calls, 1);
    #1;
    `checkh(shared_net, 4'h1);
    release {shared_net[3], shared_net[0]};
    shared_arg = 2'b10;
    #1;
    `checkh(shared_net, 4'h0);
    `checkh(shared_calls, 1);
  end
  initial begin
    #4;
    shared_force();
    `checkh(shared_calls, 2);
    #1;
    `checkh(shared_net, 4'h8);
    shared_arg = 2'b11;
    #1;
    `checkh(shared_net, 4'h9);
    `checkh(shared_calls, 3);
    release {shared_net[3], shared_net[0]};
    shared_arg = 2'b00;
    #1;
    `checkh(shared_net, 4'h0);
    `checkh(shared_calls, 3);
  end

  // A released force does not follow a change of its value in the same time step, also when it
  // is executed in a loop
  int step_calls = 0;
  logic [1:0] step_arg = 2'b01;
  function automatic logic [1:0] step_value(logic [1:0] value);
    ++step_calls;
    return value;
  endfunction
  wire [3:0] step_net = '0;
  wire [3:0] step_concat = '0;
  task automatic step_force();
    force step_net[1:0] = step_value(step_arg);
  endtask
  initial begin
    #1;
    force step_net[1:0] = step_value(step_arg);
    force {step_concat[3], step_concat[0]} = step_value(step_arg);
    `checkh(step_calls, 2);
    #0;
    release step_net;
    release step_concat;
    step_arg = 2'b10;
    #1;
    `checkh(step_calls, 2);
    for (int i = 0; i < 3; ++i) step_force();
    `checkh(step_calls, 5);
    step_arg = 2'b01;
    #1;
    `checkh(step_net, 4'h1);
    `checkh(step_calls, 6);
    #0;
    release step_net;
    step_arg = 2'b10;
    #1;
    `checkh(step_net, 4'h0);
    `checkh(step_calls, 6);
  end

  // A force executed only by the first copy of a loop follows its value until released
  int first_calls = 0;
  logic [1:0] first_arg = 2'b01;
  function automatic logic [1:0] first_value(logic [1:0] value);
    ++first_calls;
    return value;
  endfunction
  wire [3:0] first_net = '0;
  wire [3:0] first_concat = '0;
  int first_copy = 0;
  task automatic first_force();
    force first_net[1:0] = first_value(first_arg);
    force {first_concat[2], first_concat[0]} = first_value(first_arg);
  endtask
  initial begin
    #1;
    for (int i = 0; i < 4; ++i) if (i == first_copy) first_force();
    `checkh(first_calls, 2);
    `checkh(first_net, 4'h1);
    `checkh(first_concat, 4'h1);
    #1;
    first_arg = 2'b11;
    #1;
    `checkh(first_net, 4'h3);
    `checkh(first_concat, 4'h5);
    `checkh(first_calls, 4);
    #0;
    release first_net[0];
    release first_concat[0];
    first_arg = 2'b10;
    #1;
    `checkh(first_net, 4'h2);
    `checkh(first_concat, 4'h4);
    `checkh(first_calls, 6);
    #0;
    release first_net;
    release first_concat;
    first_arg = 2'b01;
    #1;
    `checkh(first_net, 4'h0);
    `checkh(first_concat, 4'h0);
    `checkh(first_calls, 6);
  end

  // A force executed by some copies of a loop under a condition follows its value until released
  int cond_calls = 0;
  logic [1:0] cond_arg = 2'd3;
  bit cond_enable[4] = '{1, 0, 1, 0};
  function automatic logic [1:0] cond_value(logic [1:0] value);
    ++cond_calls;
    return value;
  endfunction
  wire [3:0] cond_net = '0;
  wire [3:0] cond_concat = '0;
  task automatic cond_force();
    force {cond_concat[3], cond_concat[0]} = cond_value(cond_arg);
  endtask
  initial begin
    #1;
    for (int i = 0; i < 4; ++i) if (cond_enable[i]) force cond_net[3:2] = cond_value(cond_arg);
    `checkh(cond_calls, 2);
    `checkh(cond_net, 4'hc);
    #1;
    cond_arg = 2'd1;
    #1;
    `checkh(cond_net, 4'h4);
    `checkh(cond_calls, 3);
    release cond_net;
    cond_arg = 2'd2;
    #1;
    `checkh(cond_net, 4'h0);
    `checkh(cond_calls, 3);
    cond_arg = 2'b01;
    for (int i = 0; i < 4; ++i) if (cond_enable[i]) cond_force();
    `checkh(cond_calls, 5);
    #1;
    `checkh(cond_concat, 4'h1);
    cond_arg = 2'b10;
    #1;
    `checkh(cond_concat, 4'h8);
    `checkh(cond_calls, 6);
    release cond_concat[0];
    cond_arg = 2'b11;
    #1;
    `checkh(cond_concat, 4'h8);
    `checkh(cond_calls, 7);
    #0;
    release cond_concat[3];
    cond_arg = 2'b01;
    #1;
    `checkh(cond_concat, 4'h0);
    `checkh(cond_calls, 7);
  end

endmodule
