// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checks(gotv,expv) do if ((gotv) != (expv)) begin $write("%%Error: %s:%0d: got='%s' exp='%s'\n", `__FILE__, `__LINE__, (gotv), (expv)); `stop; end while(0);
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%0d exp=%0d\n", `__FILE__, `__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

package capture_inputs;
  typedef enum bit [6:0] {
    IDLE = 7'd1,
    BUSY = 7'd65
  } state_t;
  int calls = 0;
  int startup_calls = 0;
  bit selected;

  function automatic state_t next_enum();
    ++calls;
    return calls[0] ? BUSY : IDLE;
  endfunction

  function automatic state_t startup_enum();
    ++startup_calls;
    return BUSY;
  endfunction

  function automatic state_t selected_enum();
    return selected ? BUSY : IDLE;
  endfunction
endpackage

class Echo;
  static function string text(input string value);
    return value;
  endfunction
endclass

class Initialized;
  static string text = $sformatf("%p", capture_inputs::startup_enum());
endclass

class Consumer;
  string saved;
  function new(input string value = Echo::text($sformatf("%p", capture_inputs::next_enum())));
    saved = value;
  endfunction
  function string render(input string value = $sformatf("%p", capture_inputs::next_enum()));
    return value;
  endfunction
endclass

module t;
  import capture_inputs::*;
  bit scope_done;
  capture_name_scopes scope_test(scope_done);

  function automatic string render(input string value = Echo::text($sformatf("%p", next_enum())));
    return value;
  endfunction
`ifdef TEST_ENUM_STRING_COMPAT
  // Fork-specific enum-name %s compatibility is exercised by the VLT-only companion.
  function automatic string render_string(input string value = $sformatf("%s", next_enum()));
    return value;
  endfunction
`endif
  function automatic string recursive(
      input int depth, input string value = Echo::text($sformatf("%p", next_enum())));
    if (depth == 0) return value;
    return {value, "/", recursive(depth - 1)};
  endfunction

  // A static initializer executes outside this subroutine, only once.
  function automatic string static_value();
    static string saved = $sformatf("%p", startup_enum());
    return saved;
  endfunction
  string initialized = $sformatf("%p", startup_enum());

  function automatic string continuous_value(input string value = Echo::text(
                                             $sformatf("%p", selected_enum())));
    return value;
  endfunction
  string continuous_text;
  assign continuous_text = continuous_value();

  initial begin
    string value;
    string expected;
    int before_calls;
    int before_startup;
    Consumer obj;
    calls = 0;
    before_startup = startup_calls;
    value = static_value();
    `checks(value, "BUSY");
    value = static_value();
    `checks(value, "BUSY");
    `checks(initialized, "BUSY");
    `checks(Initialized::text, "BUSY");
    `checkd(startup_calls, before_startup);

    for (int i = 0; i < 32; ++i) begin
      before_calls = calls;
      value = render();
      expected = calls[0] ? "BUSY" : "IDLE";
      `checks(value, expected);
      `checkd(calls, before_calls + 1);
      value = render("explicit");
      `checks(value, "explicit");
      `checkd(calls, before_calls + 1);

`ifdef TEST_ENUM_STRING_COMPAT
      before_calls = calls;
      value = render_string();
      expected = calls[0] ? "BUSY" : "IDLE";
      `checks(value, expected);
      `checkd(calls, before_calls + 1);
`endif

      before_calls = calls;
      obj = new();
      expected = calls[0] ? "BUSY" : "IDLE";
      `checks(obj.saved, expected);
      `checkd(calls, before_calls + 1);
      before_calls = calls;
      value = obj.render();
      expected = calls[0] ? "BUSY" : "IDLE";
      `checks(value, expected);
      `checkd(calls, before_calls + 1);

      before_calls = calls;
      value = recursive(2);
      expected = before_calls[0] ? "IDLE/BUSY/IDLE" : "BUSY/IDLE/BUSY";
      `checks(value, expected);
      `checkd(calls, before_calls + 3);

      selected = i[0];
      #1;
      expected = selected ? "BUSY" : "IDLE";
      `checks(continuous_text, expected);
    end
    `checkd(scope_done, 1);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule

module capture_name_scopes(output bit done);
  typedef enum bit {IDLE, BUSY} state_t;
  int scope_calls = 0;

  function automatic state_t next_enum();
    ++scope_calls;
    return scope_calls[0] ? BUSY : IDLE;
  endfunction

  function automatic string render(input string value = $sformatf("%p", next_enum()));
    return value;
  endfunction

  string direct_before;
  string default_before;
  initial begin
    direct_before = $sformatf("%p", next_enum());
    default_before = render();
  end

  // This class visit separates two groups of parent-scope capture declarations.
  class Boundary;
    static function string text(input state_t value);
      return $sformatf("%p", value.next());
    endfunction
  endclass

  initial begin
    string direct_after;
    string default_after;
    #1;
    `checks(direct_before, "BUSY");
    `checks(default_before, "IDLE");
    `checkd(scope_calls, 2);
    direct_after = $sformatf("%p", next_enum());
    default_after = render();
    `checks(direct_after, "BUSY");
    `checks(default_after, "IDLE");
    `checkd(scope_calls, 4);
    `checks(render("explicit"), "explicit");
    `checkd(scope_calls, 4);
    `checks(Boundary::text(IDLE), "BUSY");
    `checks(Boundary::text(BUSY), "IDLE");
    done = 1;
  end
endmodule
