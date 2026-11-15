// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;
  typedef enum bit {
    IDLE,
    BUSY
  } state_t;
  bit flip;

  function automatic state_t next_enum();
    flip = ~flip;
    return flip ? BUSY : IDLE;
  endfunction

  class Sink;
    static function string echo(input string text);
      return text;
    endfunction
  endclass

  function automatic string render(input string text = Sink::echo($sformatf("%p", next_enum())));
    return text;
  endfunction

  string first;
  string continual;
  initial begin
    first = render();
    $display("%s", first);
  end
  assign continual = render();
  initial $display("%s", continual);
endmodule
