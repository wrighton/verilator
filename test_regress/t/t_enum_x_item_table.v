// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Enum value tables in the constant pool hold an item with X bits, under
// the driver's --x-assign unique: basic randomization, next() and prev()

typedef enum logic [1:0] {
  F0 = 2'b00,
  FX = 2'b1x,
  F1 = 2'b01
} four_e;

class Plain;
  rand four_e f;
endclass

module t;
  initial begin
    Plain p;
    four_e e;
    bit seen[four_e];
    int ok;
    p = new;
    repeat (40) begin
      ok = p.randomize();
      `checkd(ok, 1);
      // The X bit of FX is a fixed 0 in the table
      `checkd(p.f != 2'b11, 1'b1);
      seen[p.f] = 1;
      if (p.f != 2'b10) begin  // next()/prev() of FX, which is not 2-state, are undefined
        e = p.f;
        e = e.next();
        `checkd(2'(e), p.f == F0 ? 2'b10 : 2'b00);  // FX or F0
        e = p.f;
        e = e.prev();
        `checkd(2'(e), p.f == F0 ? 2'b01 : 2'b10);  // F1 or FX
      end
    end
    `checkd(seen.size(), 3);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
