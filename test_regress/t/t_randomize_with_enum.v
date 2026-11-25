// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Antmicro
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define checkinrange(gotv,minv,maxv) do if (((minv) > (gotv)) || ((maxv) < (gotv))) begin $write("%%Error: %s:%0d: got=%0d min=%0d max=%0d\n", `__FILE__,`__LINE__, (gotv), (minv), (maxv)); `stop; end while(0);
// verilog_format: on

typedef enum bit [3:0] {
  ONE,
  TWO,
  THREE,
  FOUR,
  FIVE
} enum_t;

class withConstraint;
  rand enum_t e;

  constraint c {e != ONE;}
endclass

class withoutConstraint;
  rand enum_t e;
  rand enum_t f;
endclass

package format_constraint;
  class formatTarget;
    rand int unsigned sample;
    constraint sample_range {sample inside {[0:127]};}
  endclass

  typedef enum bit [6:0] {IDLE = 7'd1, BUSY = 7'd65} state_t;

  function automatic state_t choose_state(input bit selector);
    return selector ? BUSY : IDLE;
  endfunction

  function automatic void exercise(formatTarget target);
    bit selector;
    string expected;
    int result;
    for (int iteration = 0; iteration < 8; ++iteration) begin
      selector = iteration[0];
      expected = selector ? "BUSY" : "IDLE";
      result = target.randomize() with {
        sample == (selector ? 32'd65 : 32'd1);
        $sformatf("%p", choose_state(selector)) == expected;
      };
      `checkd(result, 1);
      `checkd(target.sample, selector ? 32'd65 : 32'd1);

      // The enum predicate must reject an otherwise satisfiable randomization.
      expected = selector ? "IDLE" : "BUSY";
      target.sample = 32'd97;
      result = target.randomize() with {
        sample == (selector ? 32'd65 : 32'd1);
        $sformatf("%p", choose_state(selector)) == expected;
      };
      `checkd(result, 0);
      `checkd(target.sample, 32'd97);
    end
  endfunction
endpackage

module t;
  withConstraint wc;
  withoutConstraint woc;

  typedef enum bit [6:0] {IDLE = 7'd1, BUSY = 7'd65} state_t;

  function automatic state_t choose_state(input bit selector);
    return selector ? BUSY : IDLE;
  endfunction

  initial begin
    int rand_result;
    wc = new;
    woc = new;

    repeat (20) begin
      rand_result = wc.randomize();
      `checkd(rand_result, 1);
      `checkinrange(int'(wc.e), int'(TWO), int'(FIVE));

      rand_result = woc.randomize();
      `checkd(rand_result, 1);
      `checkinrange(int'(woc.e), int'(ONE), int'(FIVE));

      rand_result = (wc.randomize() with {e != TWO;});
      `checkd(rand_result, 1);
      `checkinrange(int'(wc.e), int'(THREE), int'(FIVE));

      rand_result = (woc.randomize() with {e != ONE;});
      `checkd(rand_result, 1);
      `checkinrange(int'(woc.e), int'(TWO), int'(FIVE));
      `checkinrange(int'(woc.f), int'(ONE), int'(FIVE));

      rand_result = (woc.randomize() with {
        e != ONE;
        f != ONE;
      });
      `checkd(rand_result, 1);
      `checkinrange(int'(woc.e), int'(TWO), int'(FIVE));
      `checkinrange(int'(woc.f), int'(TWO), int'(FIVE));
    end

    begin
      bit selector;
      state_t wanted;
      int unsigned sample;
      int result;
      for (int iteration = 0; iteration < 8; ++iteration) begin
        selector = iteration[0];
        wanted = choose_state(selector);
        result = std::randomize(sample) with {
          sample == (selector ? 32'd65 : 32'd1);
          choose_state(selector).name() == wanted.name();
          // Formatting a nonconstant enum expression creates an owned temporary.
          $sformatf("%p", choose_state(selector)) == wanted.name();
        };
        `checkd(result, 1);
        `checkd(sample, selector ? 32'd65 : 32'd1);
        `checkd(wanted, selector ? BUSY : IDLE);

        wanted = selector ? IDLE : BUSY;
        sample = 32'd97;
        result = std::randomize(sample) with {
          sample == (selector ? 32'd65 : 32'd1);
          $sformatf("%p", choose_state(selector)) == wanted.name();
        };
        `checkd(result, 0);
        `checkd(sample, 32'd97);
      end
    end

    begin
      format_constraint::formatTarget target;
      target = new;
      format_constraint::exercise(target);
    end

    $write("*-* all finished *-*\n");
    $finish;
  end
endmodule
