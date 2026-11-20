// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%h exp=%h\n", `__FILE__, `__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

interface value_pin_driver (
    output wire p,
    input wire value,
    input wire enable
);
  assign p = enable ? value : 1'bz;
endinterface

module value_pin_written (
    input wire p,
    input wire value,
    input wire enable,
    output wire seen
);
  assign seen = p;
endmodule
bind value_pin_written value_pin_driver driver (.p(p), .value(value), .enable(enable));

module value_pin_read (
    input wire p,
    output wire seen
);
  assign seen = p;
endmodule

module plain_value_pin_driver (
    output wire [3:0] p,
    input wire [3:0] value
);
  assign p = value;
endmodule

module plain_value_pin_sink (
    input wire [3:0] p,
    input wire [3:0] value,
    output wire [3:0] seen
);
  assign seen = p;
endmodule
bind plain_value_pin_sink plain_value_pin_driver driver (.p(p), .value(value));

module width_value_pin_sink (
    input wire [1:0] p,
    input wire [1:0] value,
    output wire [1:0] seen
);
  assign seen = p;
endmodule
bind width_value_pin_sink plain_value_pin_driver2 driver (.p(p), .value(value));

module plain_value_pin_driver2 (
    output wire [1:0] p,
    input wire [1:0] value
);
  assign p = value;
endmodule

module repeat_route_driver (
    output wire p,
    input wire v
);
  assign p = v;
endmodule

module repeat_route_sink (
    input wire p,
    input wire v,
    output wire seen
);
  assign seen = p;
endmodule
bind repeat_route_sink repeat_route_driver d (
    .p(p),
    .v(v)
);

module repeat_route_case (
    output bit done
);
  typedef struct packed {logic f;} P;
  logic v;
  logic en;
  wire a = en ? v : 1'bz;
  wire b = en ? v : 1'bz;
  wire c = en ? v : 1'bz;
  wire s1, s2, s3, s4;
  localparam int N = 1;
  repeat_route_sink s (
      .p({a}),
      .v(v),
      .seen(s1)
  );
  repeat_route_sink r (
      .p({1{b}}),
      .v(v),
      .seen(s2)
  );
  repeat_route_sink rp (
      .p({N{c}}),
      .v(v),
      .seen(s3)
  );
  repeat_route_sink val (
      .p(P'{default: 1'bz}),
      .v(v),
      .seen(s4)
  );
  // A select of a replication is a value too
  wire s5, s6, s7, s8;
  repeat_route_sink rs_bit (
      .p({2{c}}[0]),
      .v(v),
      .seen(s5)
  );
  repeat_route_sink rs_range (
      .p({2{c}}[0:0]),
      .v(v),
      .seen(s6)
  );
  repeat_route_sink rs_plus (
      .p({2{c}}[0+:1]),
      .v(v),
      .seen(s7)
  );
  repeat_route_sink rs_minus (
      .p({2{c}}[0-:1]),
      .v(v),
      .seen(s8)
  );
  initial begin
    for (int i = 0; i < 4; ++i) begin
      en = i[1];
      v = i[0];
      #1;
      `checkh({s1, s2, s3, s4, s5, s6, s7, s8}, {8{v}});
      `checkh(a, v);
      if (en) begin
        `checkh(b, v);
        `checkh(c, v);
      end else begin
        `checkh(b, 1'bz);
        `checkh(c, 1'bz);
      end
    end
    done = 1;
  end
endmodule

// Each element of a multidimensional instance array connects to its own bit of the vector
// (IEEE 1800-2023 23.3.3.5), and the element's driver reaches that bit
module array_route_sink (
    input wire p,
    input wire v,
    output wire seen
);
  assign seen = p;
endmodule
bind array_route_sink repeat_route_driver d (
    .p(p),
    .v(v)
);

module array_route_case (
    output bit done
);
  wire [3:0] bus;
  logic [3:0] v;
  wire [3:0] seen;
  array_route_sink u[1:0][1:0] (
      .p(bus),
      .v(v),
      .seen(seen)
  );
  initial begin
    for (int i = 0; i < 4; ++i) begin
      v = 4'(i * 5);
      #1;
      `checkh(bus, v);
      `checkh(seen, v);
    end
    done = 1;
  end
endmodule

// Each element of an unpacked array of nets connects to its own instance array element
// (IEEE 1800-2023 23.3.3.5), and the element's driver reaches it
module array_element_route_case (
    output bit done
);
  wire actual[1:0];
  logic [1:0] v;
  wire [1:0] seen;
  array_route_sink u[1:0] (
      .p(actual),
      .v(v),
      .seen(seen)
  );
  initial begin
    for (int i = 0; i < 4; ++i) begin
      v = 2'(i);
      #1;
      `checkh(actual[1], v[1]);
      `checkh(actual[0], v[0]);
      `checkh(seen, v);
    end
    done = 1;
  end
endmodule

// A value-only connection of another instance lets an already driven net receive the local
// drive, whether that connection is a variable or a value expression
module spell_driver (
    output wire p,
    input wire value
);
  assign p = value;
endmodule

module spell_var_sink (
    input wire p,
    input wire value,
    output wire seen
);
  assign seen = p;
endmodule
bind spell_var_sink spell_driver d (
    .p(p),
    .value(value)
);

module spell_repl_sink (
    input wire p,
    input wire value,
    output wire seen
);
  assign seen = p;
endmodule
bind spell_repl_sink spell_driver d (
    .p(p),
    .value(value)
);

module spell_case (
    output bit done
);
  logic v;
  logic ext_en;
  logic a;
  wire var_net = ext_en ? v : 1'bz;
  wire repl_net = ext_en ? v : 1'bz;
  wire var_seen, var_other_seen, repl_seen, repl_other_seen;
  spell_var_sink var_net_sink (
      .p(var_net),
      .value(v),
      .seen(var_seen)
  );
  spell_var_sink var_other (
      .p(a),
      .value(v),
      .seen(var_other_seen)
  );
  spell_repl_sink repl_net_sink (
      .p(repl_net),
      .value(v),
      .seen(repl_seen)
  );
  spell_repl_sink repl_other (
      .p({1{a}}),
      .value(v),
      .seen(repl_other_seen)
  );
  initial begin
    a = 1'b0;
    for (int i = 0; i < 4; ++i) begin
      ext_en = i[1];
      v = i[0];
      #1;
      // Released externally, the net carries the local drive
      `checkh(var_net, v);
      `checkh(repl_net, v);
      `checkh(var_seen, v);
      `checkh(repl_seen, v);
    end
    done = 1;
  end
endmodule

// The same instance array elements with an independently driven bus, and a sibling instance
// connected to a variable: the released bus still receives each element's drive
module mixed_array_sink (
    input wire p,
    input wire v,
    output wire seen
);
  assign seen = p;
endmodule
bind mixed_array_sink repeat_route_driver d (
    .p(p),
    .v(v)
);

module mixed_array_case (
    output bit done
);
  logic [3:0] v;
  logic ext_en;
  logic other;
  wire [3:0] bus = ext_en ? ~v : 4'bzzzz;
  wire [3:0] seen;
  wire other_seen;
  mixed_array_sink u[1:0][1:0] (
      .p(bus),
      .v(v),
      .seen(seen)
  );
  mixed_array_sink sibling (
      .p(other),
      .v(v[0]),
      .seen(other_seen)
  );
  // The elements of a concatenation receive their drive too
  wire [1:0] cat_high_bus = ext_en ? ~v[3:2] : 2'bzz;
  wire cat_low = ext_en ? ~v[1] : 1'bz;
  wire [1:0] cat_seen;
  mixed_array_sink u_cat[1:0] (
      .p({cat_high_bus[1], cat_low}),
      .v(v[2:1]),
      .seen(cat_seen)
  );
  initial begin
    other = 1'b0;
    ext_en = 1'b0;
    for (int i = 0; i < 4; ++i) begin
      v = 4'(i * 5);
      #1;
      `checkh(bus, v);
      `checkh(seen, v);
      `checkh(other, 1'b0);
      `checkh({cat_high_bus[1], cat_low}, v[2:1]);
      `checkh(cat_seen, v[2:1]);
    end
    done = 1;
  end
endmodule

// A runtime select of a net, or a hierarchical reference to a variable, is a value like a
// count-one replication of it
module runtime_spell_sink (
    input wire p,
    input wire value,
    output wire seen
);
  assign seen = p;
endmodule
bind runtime_spell_sink spell_driver d (
    .p(p),
    .value(value)
);

module runtime_repl_sink (
    input wire p,
    input wire value,
    output wire seen
);
  assign seen = p;
endmodule
bind runtime_repl_sink spell_driver d (
    .p(p),
    .value(value)
);

module hier_spell_sink (
    input wire p,
    input wire value,
    output wire seen
);
  assign seen = p;
endmodule
bind hier_spell_sink spell_driver d (
    .p(p),
    .value(value)
);

module hier_repl_sink (
    input wire p,
    input wire value,
    output wire seen
);
  assign seen = p;
endmodule
bind hier_repl_sink spell_driver d (
    .p(p),
    .value(value)
);

module hier_holder;
  logic held = 1'b0;
endmodule

module runtime_spell_case (
    output bit done
);
  logic v;
  logic ext_en;
  int idx = 0;
  wire [3:0] source = 4'b0101;
  wire select_net = ext_en ? v : 1'bz;
  wire repl_net = ext_en ? v : 1'bz;
  wire hier_net = ext_en ? v : 1'bz;
  wire hier_repl_net = ext_en ? v : 1'bz;
  wire s0, s1, s2, s3, s4, s5, s6, s7;
  hier_holder holder ();
  runtime_spell_sink select_net_sink (
      .p(select_net),
      .value(v),
      .seen(s0)
  );
  runtime_spell_sink select_other (
      .p(source[idx]),
      .value(v),
      .seen(s1)
  );
  runtime_repl_sink repl_net_sink (
      .p(repl_net),
      .value(v),
      .seen(s2)
  );
  runtime_repl_sink repl_other (
      .p({1{source[idx]}}),
      .value(v),
      .seen(s3)
  );
  hier_spell_sink hier_net_sink (
      .p(hier_net),
      .value(v),
      .seen(s4)
  );
  hier_spell_sink hier_other (
      .p(holder.held),
      .value(v),
      .seen(s5)
  );
  hier_repl_sink hier_repl_net_sink (
      .p(hier_repl_net),
      .value(v),
      .seen(s6)
  );
  hier_repl_sink hier_repl_other (
      .p({1{holder.held}}),
      .value(v),
      .seen(s7)
  );
  initial begin
    ext_en = 1'b0;
    for (int i = 0; i < 4; ++i) begin
      v = i[0];
      idx = i;
      #1;
      // Released externally, each net carries the local drive, whatever the spelling of
      // the value connection of its sibling
      `checkh(select_net, v);
      `checkh(repl_net, v);
      `checkh(hier_net, v);
      `checkh(hier_repl_net, v);
      // The values are not driven in reverse
      `checkh(source, 4'b0101);
      `checkh(holder.held, 1'b0);
    end
    done = 1;
  end
endmodule

// The width of an indexed part-select, and the indices of a range, are constant expressions
// even when they call a function, so such a select of a net is a destination like one with
// literal constants
module count_function_sink (
    input wire [1:0] p,
    input wire [1:0] value
);
endmodule
bind count_function_sink plain_value_pin_driver2 driver (.p(p), .value(value));
module count_literal_sink (
    input wire [1:0] p,
    input wire [1:0] value
);
endmodule
bind count_literal_sink plain_value_pin_driver2 driver (.p(p), .value(value));
module range_function_sink (
    input wire [1:0] p,
    input wire [1:0] value
);
endmodule
bind range_function_sink plain_value_pin_driver2 driver (.p(p), .value(value));

module count_case (
    output bit done
);
  function automatic int count();
    return 2;
  endfunction
  function automatic int high();
    return 1;
  endfunction
  logic [1:0] drive;
  wire [3:0] function_bus;
  wire [3:0] literal_bus;
  wire [3:0] range_bus;
  count_function_sink function_count (
      .p(function_bus[0+:count()]),
      .value(drive)
  );
  count_literal_sink literal_count (
      .p(literal_bus[0+:2]),
      .value(drive)
  );
  range_function_sink function_range (
      .p(range_bus[high():0]),
      .value(drive)
  );
  initial begin
    for (int i = 0; i < 4; ++i) begin
      drive = 2'(i);
      #1;
      `checkh(function_bus[1:0], drive);
      `checkh(literal_bus[1:0], drive);
      `checkh(range_bus[1:0], drive);
    end
    done = 1;
  end
endmodule

module t;
  wire repeat_done, array_done, element_done, spell_done, mixed_array_done, runtime_spell_done;
  wire count_done;
  repeat_route_case repeats (.done(repeat_done));
  array_route_case arrays (.done(array_done));
  array_element_route_case elements (.done(element_done));
  spell_case spellings (.done(spell_done));
  mixed_array_case mixed_arrays (.done(mixed_array_done));
  runtime_spell_case runtime_spellings (.done(runtime_spell_done));
  count_case counts (.done(count_done));
  typedef struct packed {logic b;} single_t;
  logic bound_value;
  logic bound_enable;
  logic forward_value;
  logic expected_bound;
  wire rejected_value;
  wire direct_net;
  wire driven_net;
  wire driven_seen;
  logic external_enable;
  assign driven_net = external_enable ? bound_value : 1'bz;
  wire forward_net = forward_value;
  wire bound_seen;
  wire direct_seen;
  wire forward_seen;
  value_pin_written u_rejected (
      .p(single_t'{default: rejected_value}),
      .value(bound_value), .enable(bound_enable), .seen(bound_seen)
  );
  // The same formal cannot be coerced, but its ordinary net actual still collapses.
  value_pin_written u_direct (
      .p(direct_net), .value(bound_value), .enable(bound_enable), .seen(direct_seen)
  );
  value_pin_written u_driven (
      .p(driven_net), .value(bound_value), .enable(bound_enable), .seen(driven_seen)
  );
  value_pin_read u_forward (.p(single_t'{default: forward_net}), .seen(forward_seen));

  // Full-width selects may fold to references after Width. Keep their actuals one-way.
  typedef struct packed {logic [3:0] bits;} single_vec_t;
  logic [3:0] external_drive;
  logic [3:0] internal_drive;
  wire [3:0] independent = external_drive;
  wire [3:0] floating;
  wire [3:0] folded_seen, floating_seen;
  plain_value_pin_sink u_folded (
      .p(single_vec_t'{default: independent[3:0]}), .value(internal_drive), .seen(folded_seen)
  );
  plain_value_pin_sink u_floating (
      .p(single_vec_t'{default: floating}), .value(internal_drive), .seen(floating_seen)
  );

  // Input sizing is forward-only; a source part-select is an actual destination.
  typedef struct packed {logic hi; logic lo;} pair_t;
  logic [1:0] width_drive;
  wire [3:0] wide_whole = external_enable ? {2'b11, width_drive} : 4'bzzzz;
  wire [3:0] wide_slice = external_enable ? {2'b11, width_drive} : 4'bzzzz;
  wire [1:0] whole_seen, slice_seen, width_value_seen;
  // A wider net truncated to the port is the case under test
  // verilator lint_off WIDTHTRUNC
  width_value_pin_sink u_whole (.p(wide_whole), .value(width_drive), .seen(whole_seen));
  // verilator lint_on WIDTHTRUNC
  width_value_pin_sink u_slice (.p(wide_slice[1:0]), .value(width_drive), .seen(slice_seen));
  width_value_pin_sink u_width_value (
      .p(pair_t'{default: 1'bz}), .value(width_drive), .seen(width_value_seen)
  );

  initial begin
    for (int i = 0; i < 8; ++i) begin
      width_drive = i[0] ? 2'b10 : 2'b01;
      external_drive = 4'(i * 3);
      internal_drive = i[0] ? ~external_drive : external_drive;
      bound_value = i[0];
      forward_value = i[1];
      bound_enable = !i[2];
      external_enable = i[1];
      expected_bound = bound_enable ? bound_value : 1'bz;
      #1;
      `checkh(bound_seen, expected_bound);
      `checkh(direct_seen, expected_bound);
      `checkh(direct_net, expected_bound);
      if (!i[2] || !i[1]) begin
        `checkh(driven_net, expected_bound);
        `checkh(driven_seen, expected_bound);
      end else begin
        `checkh(driven_net, bound_value);
        `checkh(driven_seen, bound_value);
      end
      `checkh(forward_seen, forward_value);
      `checkh(rejected_value, 1'bz);
      `checkh(independent, external_drive);
      `checkh(floating, 4'bzzzz);
      `checkh(floating_seen, internal_drive);
      // When both sources agree the resolved formal has a known value. Do not
      // assert a binary value in the conflicting samples.
      if (!i[0]) `checkh(folded_seen, external_drive);
      `checkh(whole_seen, width_drive);
      `checkh(slice_seen, width_drive);
      `checkh(width_value_seen, width_drive);
      `checkh(wide_slice[1:0], width_drive);
      if (external_enable) begin
        `checkh(wide_slice[3:2], 2'b11);
        `checkh(wide_whole, {2'b11, width_drive});
      end else begin
        `checkh(wide_slice[3:2], 2'bzz);
        `checkh(wide_whole, 4'bzzzz);
      end
    end
    wait (repeat_done && array_done && element_done && spell_done && mixed_array_done
          && runtime_spell_done && count_done);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
