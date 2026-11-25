// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define checks(gotv,expv) do if ((gotv) != (expv)) begin $write("%%Error: %s:%0d:  got='%s' exp='%s'\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Array elements of events deleted, moved or copied within the time step they
// are triggered in (IEEE 1800-2023 15.5.3)
module t;
`ifdef TEST_ASSIGNABLE
  // The same cases in a design that assigns events
  class EventPair;
    event assigned_from;
    event assigned_to;
    function void merge();
      assigned_to = assigned_from;
    endfunction
  endclass
  initial begin
    EventPair pair;
    pair = new;
    pair.merge();
  end
`endif

  // Test: elements of dynamic, queue and associative arrays deleted in the time step
  initial begin
    event d[];
    event q[$];
    event a[int];
    repeat (3) begin
      d = new[1000];
      ->d[900];
      d.delete();
      q = {};
      repeat (5) q.push_back(d[0]);
      ->q[4];
      void'(q.pop_back());
      ->a[5];
      a.delete(5);
      #1;
    end
  end

  // Test: queue elements moved by insert and delete, and copies of a triggered event
  initial begin
    event x;
    event moved[$];
    event copies[$];
    repeat (4) moved.push_back(x);
    ->moved[0];
    moved.insert(1, x);
    ->moved[4];
    moved.delete(1);
    ->x;
    copies.push_back(x);
    `checkd(copies[0].triggered, 1);
    #1;
    foreach (moved[i]) `checkd(moved[i].triggered, 0);
    `checkd(copies[0].triggered, 0);
    `checks($sformatf("%p", copies), "'{event}");
  end

  initial begin
    #10;
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
