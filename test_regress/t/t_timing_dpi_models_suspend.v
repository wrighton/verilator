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


// A process whose imported task suspends in an export of another model, or calls exports of it
// that call imported tasks of it, stays the process of those tasks and of the exports they call,
// so they draw from its RNG (IEEE 1800-2023 35.5.1.5, 18.14.1)

class Rand;
  rand int unsigned m_val;
endclass

module a;
  import "DPI-C" context task a_imp(output int unsigned drawn);
  import "DPI-C" context task a_imp_nested(
    output int unsigned drawn,
    input int depth
  );
  // Makes imported tasks run on a worker, so they may call exports that suspend
  export "DPI-C" task a_wait;
  task a_wait();
    #1;
  endtask
  export "DPI-C" function a_touch;
  process touched;
  function void a_touch();
    touched = process::self();
  endfunction

  initial begin
    process p;
    Rand r;
    int unsigned expDrawn;
    int unsigned gotDrawn;
    string expState;
    int depth;
    p = process::self();

    // Calls exports of model b that call imported tasks of model b, the last of which draws in a
    // function of model b without a process: through two tasks, through one, and through one
    // waiting after it
    for (int i = 0; i < 3; ++i) begin
      depth = (i + 2) % 3;
      p.srandom(43 + depth);
      expDrawn = $urandom;
      expState = p.get_randstate();
      p.srandom(43 + depth);
      a_imp_nested(gotDrawn, depth);
      `checkh(gotDrawn, expDrawn);
      `checks(p.get_randstate(), expState);
    end

    p.srandom(42);
    expDrawn = $urandom;
    r = new;
    expState = r.get_randstate();
    p.srandom(42);
    // Waits in model b, then draws in a function of model b without a process, then calls a
    // function taking a process in this model
    a_imp(gotDrawn);
    `checkh(gotDrawn, expDrawn);
    r = new;
    `checks(r.get_randstate(), expState);
    `checkh(touched == p, 1'b1);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule

module b;
  import "DPI-C" context function void b_save_scope();
  initial b_save_scope();
  export "DPI-C" task b_wait;
  task b_wait();
    #1;
  endtask
  import "DPI-C" context task b_imp();
  import "DPI-C" context task b_imp_deep();
  export "DPI-C" task b_entry;
  task b_entry();
    b_imp();
  endtask
  export "DPI-C" task b_entry_wait;
  task b_entry_wait();
    b_imp();
    #1;
  endtask
  export "DPI-C" task b_entry_deep;
  task b_entry_deep();
    b_imp_deep();
  endtask
  export "DPI-C" function b_rand;
  function int unsigned b_rand();
    return $urandom;
  endfunction
endmodule
