// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2023 Antmicro Ltd
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
// verilog_format: on

event evt1, evt2;

class Foo;
  process p;
  bit event_received;

  function new();
    p = process::self();
  endfunction

  virtual task ewait();
    @evt1 $display("Foo received event `evt1`");
    event_received = 1;
    ->evt2;
  endtask
endclass

class Bar extends Foo;
  function new();
    super.new();
    $display("Constructing Bar");
  endfunction

  virtual task ewait();
    @evt1 $display("Bar received event `evt1`");
    event_received = 1;
  endtask
endclass

// A subroutine needing the current process, called by a task both directly and from a fork
// branch, gets the caller's process on the direct call
class Rec;
  static process last;
  static function void record();
    last = process::self();
  endfunction
  static task recordTwice();
    record();
    fork
      record();
    join_none
  endtask
endclass

module t;
  initial begin
    automatic process p = process::self();
    Rec::recordTwice();
    if (Rec::last != p) `stop;
    #1;
    if (Rec::last == p) `stop;
  end

  initial begin
    process p;
    Foo foo;
    Bar bar;

    fork
      begin
        foo = new;
        foo.ewait();
      end
      begin
        bar = new;
        p = process::self();
        bar.ewait();
      end
    join_none
    #1;
    p.kill();

    ->evt1;

    @evt2 begin
      if (!foo.event_received) `stop;
      if (bar.event_received) `stop;

      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
