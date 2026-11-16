// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;
  typedef enum bit [1:0] {IDLE = 2'd1, BUSY = 2'd2} state_t;
  bit selected;
  string text;
  string task_text;
  string forced_text;

  function automatic state_t choose(input bit sel);
    return sel ? BUSY : IDLE;
  endfunction

  task automatic set_text(input int n);
    if (n > 0) set_text(n - 1);
    // verilator lint_off IEEEMAYDEPRECATE
    assign task_text = $sformatf("%p", choose(selected));
    // verilator lint_on IEEEMAYDEPRECATE
  endtask

  task automatic force_text();
    force forced_text = $sformatf("%p", choose(selected));
  endtask

  initial begin
    // The values follow 'selected' after the activating statement or task returns
    // verilator lint_off IEEEMAYDEPRECATE
    assign text = $sformatf("%p", choose(selected));
    // verilator lint_on IEEEMAYDEPRECATE
    set_text(1);
    force_text();
    #1;
    selected = 1'b1;
    #1;
    $display("%s %s %s", text, task_text, forced_text);
    $finish;
  end
endmodule
