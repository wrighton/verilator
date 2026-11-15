// DESCRIPTION: Verilator: Static module-function enum default capture
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checks(gotv,expv) do if ((gotv) != (expv)) begin $write("%%Error: %s:%0d: got='%s' exp='%s'\n", `__FILE__, `__LINE__, (gotv), (expv)); `stop; end while(0);
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__, `__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

package static_capture_inputs;
  typedef enum bit [6:0] {IDLE = 7'd1, BUSY = 7'd65} state_t;
  int calls = 0;
  function automatic state_t next_enum();
    ++calls;
    return calls[0] ? BUSY : IDLE;
  endfunction
endpackage

module t;
  import static_capture_inputs::*;

  function static string render(input string value = $sformatf("%p", next_enum()));
    return value;
  endfunction

  initial begin
    string value;
    string expected;
    int before_calls;
    for (int i = 0; i < 32; ++i) begin
      before_calls = calls;
      value = render();
      expected = calls[0] ? "BUSY" : "IDLE";
      `checks(value, expected);
      `checkd(calls, before_calls + 1);
      value = render("explicit");
      `checks(value, "explicit");
      `checkd(calls, before_calls + 1);
      #1;
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
