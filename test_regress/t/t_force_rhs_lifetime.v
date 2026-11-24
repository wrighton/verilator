// DESCRIPTION: Verilator: class snapshot lifetime after force release
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

class Tracked;
`ifdef VERILATOR
  `systemc_header
  inline unsigned& force_destructions() {
      static unsigned count = 0;
      return count;
  }
  `systemc_dtor
  ++force_destructions();
  `verilog
`endif

  function automatic logic [6:0] value(logic [6:0] x);
    return x ^ 7'h5a;
  endfunction
endclass

module t;
  Tracked handle;
  Tracked objects[2];
  int index = 1;
  logic [6:0] arg = 0;
  wire [6:0] target = 7'h21;
  logic [6:0] selected;
  int deleted;
  initial begin
    #1;
    handle = new;
    force target = handle.value(arg);
    #1;
    release target[3:2];
    arg = 7'd1;
    #1;
    if (target !== 7'h53) $fatal(1, "Partial force no longer follows its argument: %0h", target);
    deleted = $c("force_destructions()");
    if (deleted != 0) $fatal(1, "Object destroyed before full release");
    release target;
    handle = null;
    arg = 7'd5;
    #2;
    deleted = $c("force_destructions()");
    if (deleted != 1) $fatal(1, "Released direct handle retained: %0d", deleted);
    if (target !== 7'h21) $fatal(1, "Net driver not restored");

    handle = new;
    objects[1] = handle;
    handle = null;
    force selected = objects[index].value(arg);
    #1;
    release selected;
    objects[1] = null;
    #2;
    deleted = $c("force_destructions()");
    if (deleted != 2) $fatal(1, "Released selected handle retained: %0d", deleted);
    if (selected !== 7'h5f) $fatal(1, "Released variable did not hold");
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
