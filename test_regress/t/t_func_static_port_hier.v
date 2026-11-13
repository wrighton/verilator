// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Ports of static tasks and functions are static, so can be referenced hierarchically
module t;
  int io;
  int o;

  task st(input int si, inout int sio, output int so);
    sio = sio + si;
    so = si + 1;
  endtask

  function int sf(input int fi);
    return fi * 2;
  endfunction

  initial begin
    io = 10;
    st(3, io, o);
    `checkd(io, 13);
    `checkd(o, 4);
    `checkd(st.si, 3);
    `checkd(st.sio, 13);
    `checkd(st.so, 4);
    `checkd(sf(5), 10);
    `checkd(sf.fi, 5);
    `checkd(sf(7), 14);
    `checkd(sf.fi, 7);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
