// DESCRIPTION: Verilator: a blocked mailbox call in a concurrent assertion action
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__, `__LINE__, (gotv), (expv)); $stop; end while(0);
// verilog_format: on

module typed_mailbox_case (
    output bit done
);
  timeunit 1ns; timeprecision 1ps;
  bit clk = 0;
  initial forever #1 clk = ~clk;
  mailbox #(int) messages = new(1);
  int cyc = 0, sent = 0, received = 0, sum = 0, nbaMarker = 0;
  int first = 0, second = 0, refWrites = 0;
  always @(posedge clk) cyc <= cyc + 1;
  always @(first) begin
    if (first != 0) begin
      // Observe the ref write itself, not just a statement after get() returns.
      `checkd(nbaMarker, 17);
      ++refWrites;
    end
  end

  // This ordinary reader joins the same mailbox after the assertion action.
  initial begin
    #2;
    messages.get(second);
  end
  initial begin
    #4;
    `checkd(first, 0);
    `checkd(second, 0);
    messages.put(17);
    nbaMarker <= 17;
    #1;
    `checkd(first, 17);
    `checkd(second, 0);
    #1;
    messages.put(29);
  end

  assert property (@(posedge clk) 1'b1 until 1'b1) begin
    automatic int message;
    if (cyc == 1) begin
      // Block before the later Active waiter. Check FIFO and that the statement
      // after get() runs in Reactive, after the producer's NBA.
      messages.get(first);
      `checkd(first, nbaMarker);
    end else if (cyc > 3) begin
      // This get must block: the producer only puts on the following edge.
      messages.get(message);
      `checkd(message, received + 1);
      `checkd(message, nbaMarker);
      ++received;
      sum += message;
    end
  end

  always @(negedge clk) begin
    if (cyc > 3) begin
      ++sent;
      messages.put(sent);
      nbaMarker <= sent;
    end
  end

  always @(posedge clk) begin
    if (cyc == 13) begin
      `checkd(first, 17);
      `checkd(second, 29);
      `checkd(refWrites, 1);
      `checkd(sent, 10);
      `checkd(received, 10);
      `checkd(sum, 55);
      done = 1;
    end
  end
endmodule

module typeless_mailbox_case #(
    parameter bit PEEK = 0
) (
    output bit done
);
  timeunit 1ns; timeprecision 1ps;
  bit clk = 0;
  initial forever #1 clk = ~clk;

  mailbox messages = new;
  int cyc = 0, first = 0, second = 0, marker = 0, writes = 0;
  bit entered = 0;
  always @(posedge clk) ++cyc;
  assert property (@(posedge clk) 1'b1 until 1'b1) begin
    if (!entered) begin
      entered = 1;
      if (PEEK) messages.peek(first);
      else messages.get(first);
      `checkd(first, marker);
    end
  end

  always @(first) begin
    if (first != 0) begin
      `checkd(first, marker);
      ++writes;
    end
  end

  initial begin
    #2;
    messages.get(second);
  end

  initial begin
    #4;
    `checkd(entered, 1'b1);
    `checkd(first, 0);
    `checkd(second, 0);
    messages.put(cyc + 15);
    marker <= 17;
    #1;
    `checkd(first, 17);
    `checkd(writes, 1);
    // A peek passes the same message on. A get leaves the second reader blocked.
    `checkd(second, PEEK ? 17 : 0);
    #1;
    if (!PEEK) messages.put(cyc + 26);
    #1;
    `checkd(second, PEEK ? 17 : 29);
    done = 1;
  end
endmodule

module t;
  timeunit 1ns; timeprecision 1ps;
  bit typedDone, got, peeked;
  typed_mailbox_case typed_case (typedDone);
  typeless_mailbox_case get_case (got);
  typeless_mailbox_case #(.PEEK(1)) peek_case (peeked);
  initial begin
    wait (typedDone && got && peeked);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
