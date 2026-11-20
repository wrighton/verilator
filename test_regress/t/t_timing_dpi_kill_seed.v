// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define checks(gotv,expv) do if ((gotv) != (expv)) begin $write("%%Error: %s:%0d:  got='%s' exp='%s'\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// A process that kills a process waiting in an export called by an imported task keeps drawing
// from its own RNG, whatever unwinding that import runs (IEEE 1800-2023 18.14.1)

class Rand;
  rand int unsigned m_val;
endclass

module t;
  import "DPI-C" context task c_join_in_sv();
  export "DPI-C" task sv_join;
  task sv_join();
    fork
      #10;
    join
  endtask

  process victim;
  initial begin
    victim = process::self();
    c_join_in_sv();
  end

  initial begin
    process p;
    Rand r;
    string expState;
    #1;
    p = process::self();
    p.srandom(42);
    r = new;
    expState = r.get_randstate();
    p.srandom(42);
    victim.kill();
    r = new;
    `checks(r.get_randstate(), expState);
    `checkh(victim.status(), process::KILLED);
    #20;
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
