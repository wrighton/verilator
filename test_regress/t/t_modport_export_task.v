// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 PlanV GmbH
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0)
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0)
// verilog_format: on

interface bus_if;
  logic [7:0] data;
  logic [7:0] result;
  int q[$];
  int sum;

  modport provider(
      output data,
      output result,
      export task send(input logic [7:0] val),
      export task accumulate(input logic [7:0] a, input logic [7:0] b),
      export task add_items(input int n),
      export function int doubled_sum()
  );

  modport consumer(
      input data,
      input result,
      import task send(input logic [7:0] val),
      import task accumulate(input logic [7:0] a, input logic [7:0] b),
      import task add_items(input int n),
      import function int doubled_sum()
  );

  // Has its own unnamed block
  task clear();
    foreach (q[i]) q[i] = 0;
  endtask
endinterface

module driver (
    bus_if.provider port
);
  task port.send(input logic [7:0] val);
    port.data = val;
    port.result = val + 8'h01;
  endtask

  task port.accumulate(input logic [7:0] a, input logic [7:0] b);
    port.data = a;
    port.result = a + b;
  endtask

  // Body with its own declarations and blocks
  task port.add_items(input int n);
    int items[$];
    items.push_back(n);
    items.push_back(n + 1);
    foreach (items[i]) begin : named_blk
      int item;
      item = items[i];
      port.q.push_back(item);
    end
    foreach (port.q[i]) port.sum += port.q[i];
  endtask

  function int port.doubled_sum();
    return port.q.sum() with (item * 2);
  endfunction
endmodule

// Body with a declaration, defined before the interface is seen
interface cnt_if;
  int n;
  modport provider(output n, export task inc());
  modport consumer(input n, import task inc());
endinterface

module counter (
    cnt_if.provider port
);
  task port.inc();
    int step;
    step = 2;
    port.n += step;
  endtask
endmodule

module t;
  bus_if bif ();
  driver drv (.port(bif.provider));
  counter cnt (.port(cif.provider));
  cnt_if cif ();

  initial begin
    // Test 1: send -- multiple statements in task body
    bif.consumer.send(8'hAB);
    `checkh(bif.data, 8'hAB);
    `checkh(bif.result, 8'hAC);

    // Test 2: send again with different value
    bif.consumer.send(8'h42);
    `checkh(bif.data, 8'h42);
    `checkh(bif.result, 8'h43);

    // Test 3: accumulate -- multiple statements + two arguments
    bif.consumer.accumulate(8'h10, 8'h20);
    `checkh(bif.data, 8'h10);
    `checkh(bif.result, 8'h30);

    // Test 4: bodies with local variables, blocks and a with clause
    bif.consumer.add_items(3);
    `checkd(bif.sum, 7);
    `checkd(bif.consumer.doubled_sum(), 14);
    bif.clear();
    `checkd(bif.consumer.doubled_sum(), 0);
    cif.consumer.inc();
    `checkd(cif.n, 2);

    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
