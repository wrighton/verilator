// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

module sub (
    input int n
);
  /* verilator no_inline_module */
  function automatic int early(int x);
    if (x > 2) return 1;
    return 0;
  endfunction
  int i, j, c, acc = 0;
  // Count iterations of two loops, leaving them with the given disables
`define COUNT(then_blk, else_blk) \
    c = 0; \
    begin : done \
      for (i = 0; i < n; i++) begin : body \
        for (j = 0; j < n; j++) begin \
          if (i == 2) begin \
            c = c + 10; \
            disable then_blk; \
          end \
          else begin \
            c = c + 1; \
            disable else_blk; \
          end \
        end \
      end \
    end \
    acc = acc + c;
  // The logic of each initial block is the same in both instances, so is combined. The first two
  // differ only in the targets of their disables, so are not combined with each other. They are
  // on one line, as the line of a delay is part of its code.
  // verilog_format: off
  initial begin : first #1; `COUNT(done, body) end  initial begin : second #1; `COUNT(body, done) end
  // verilog_format: on
  int early_q, loop_q;
  initial begin
    #1;
    early_q = early(n);
    for (loop_q = 0; loop_q < 8; loop_q++) begin
      if (loop_q == n) break;
    end
  end
endmodule

module t;
  int n;
  sub u1 (.n);
  sub u2 (.n);
  initial begin
    n = 4;
    #2;
    `checkd(u1.acc, 13);
    `checkd(u1.early_q, 1);
    `checkd(u1.loop_q, 4);
    `checkd(u2.acc, 13);
    `checkd(u2.early_q, 1);
    `checkd(u2.loop_q, 4);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
