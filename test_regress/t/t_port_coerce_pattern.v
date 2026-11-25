// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d: got=%h exp=%h\n", `__FILE__, `__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

package pattern_types;
  typedef struct packed {
    logic signed [6:0] high;
    logic low;
  } pair_t;
  typedef struct packed {
    bit [6:0] high;
    bit low;
  } bits_t;
  typedef struct packed {
    logic [3:0] high;
    logic [3:0] low;
  } halves_t;
  typedef logic [4:0] five_t;
  typedef logic [2:0] three_t;
  typedef struct packed {
    five_t high;
    three_t low;
  } split_t;
endpackage

interface pattern_driver #(
    parameter int DW = 8
) (
    output wire [DW-1:0] p,
    input wire [DW-1:0] value
);
  assign p = value;
endinterface

// A bound output driver is outside the target's code; no ASSIGNIN suppression is needed.
module pattern_sink #(
    parameter type T = pattern_types::pair_t
) (
    input wire [$bits(T)-1:0] p,
    input wire [$bits(T)-1:0] value
);
endmodule
bind pattern_sink pattern_driver #($bits(
    T
)) driver (
    .p(p),
    .value(value)
);

// A named pattern is a forward value, not a destination (IEEE 1800-2023 10.9).
module named_pattern_sink (
    input wire [7:0] p,
    input wire [7:0] value
);
endmodule
bind named_pattern_sink pattern_driver driver (.p(p), .value(value));

// Separate formals for a type-keyed pattern, its positional equivalent and a select by a wide
// constant index, so each is observed independently
module typed_pattern_sink (
    input wire [7:0] p,
    input wire [7:0] value
);
endmodule
bind typed_pattern_sink pattern_driver driver (.p(p), .value(value));
module typed_control_sink (
    input wire [7:0] p,
    input wire [7:0] value
);
endmodule
bind typed_control_sink pattern_driver driver (.p(p), .value(value));
module wide_index_pattern_sink (
    input wire [7:0] p,
    input wire [7:0] value
);
endmodule
bind wide_index_pattern_sink pattern_driver driver (.p(p), .value(value));
module count_pattern_sink (
    input wire [7:0] p,
    input wire [7:0] value
);
endmodule
bind count_pattern_sink pattern_driver driver (.p(p), .value(value));

// The same declaration has a net destination and a variable value; only the net returns.
module mixed_sink (
    input wire [7:0] p,
    input wire [7:0] value
);
endmodule
bind mixed_sink pattern_driver driver (
    .p(p),
    .value(value)
);

module resolved_pattern_sink (
    input wire [7:0] p,
    input wire [7:0] value,
    output wire [7:0] observed
);
  assign observed = p;
endmodule
bind resolved_pattern_sink pattern_driver driver (.p(p), .value(value));

module late_alias_sink (
    input wire [7:0] p,
    input wire [7:0] value
);
endmodule
bind late_alias_sink pattern_driver driver (
    .p(p),
    .value(value)
);

module read_sink (
    input wire [7:0] p,
    output wire [7:0] seen
);
  assign seen = p;
endmodule

module bit_pair_read_sink (
    input wire [1:0] p,
    output wire [1:0] seen
);
  assign seen = p;
endmodule

module pattern_cases(output bit done);
  import pattern_types::*;
  logic [7:0] value;
  wire [6:0] nh;
  wire nl;
  wire [6:0] ph;
  wire pl;
  wire [15:0] selected;
  named_pattern_sink named (
      .p(pair_t'{low: nl, high: nh}),
      .value(value)
  );
  // A type-keyed pattern is a value too, although its positional equivalent, with the same
  // distinct destinations, is coerced
  wire [4:0] typed_high;
  wire [2:0] typed_low;
  wire [4:0] control_high;
  wire [2:0] control_low;
  typed_pattern_sink typed (
      .p(split_t'{five_t: typed_high, three_t: typed_low}),
      .value(value)
  );
  typed_control_sink typed_control (
      .p(split_t'{control_high, control_low}),
      .value(value)
  );
  // The width of an indexed part-select is a constant expression, also when it calls a
  // function, so the member is a destination
  function automatic int one();
    return 1;
  endfunction
  wire [7:0] counted;
  count_pattern_sink counted_member (
      .p(pair_t'{counted[7:1], counted[0+:one()]}),
      .value(value)
  );
  // An in-range index wider than 32 bits selects its exact bit
  wire [15:0] wide_selected;
  // verilator lint_off WIDTH
  wide_index_pattern_sink wide_index (
      .p(pair_t'{wide_selected[14:8], wide_selected[65'd0]}),
      .value(value)
  );
  // verilator lint_on WIDTH
  pattern_sink positional (
      .p(pair_t'{ph, pl}),
      .value(value)
  );
  pattern_sink select_net (
      // A narrow constant index selects its exact bit, so it is a destination too
      .p(pair_t'{selected[14:8], selected[4'd0]}),
      .value(value)
  );

  wire [6:0] mh;
  wire ml;
  logic [6:0] variable_h;
  logic variable_l;
  mixed_sink mixed_net (
      .p(pair_t'{mh, ml}),
      .value(value)
  );
  mixed_sink mixed_var (
      .p(pair_t'{variable_h, variable_l}),
      .value(value)
  );

  // The positional pin has an existing driver. The named pin on the same formal
  // still supplies only a value, even while the positional pin returns a drive.
  logic resolved_ext_en;
  wire [6:0] resolved_high = resolved_ext_en ? value[7:1] : 7'bzzzzzzz;
  wire resolved_low = resolved_ext_en ? value[0] : 1'bz;
  wire [6:0] resolved_named_high;
  wire resolved_named_low;
  wire [7:0] resolved_pos_seen, resolved_named_seen;
  resolved_pattern_sink resolved_pos (
      .p(pair_t'{resolved_high, resolved_low}), .value(value), .observed(resolved_pos_seen)
  );
  resolved_pattern_sink resolved_named (
      .p(pair_t'{high: resolved_named_high, low: resolved_named_low}),
      .value(value), .observed(resolved_named_seen)
  );

  logic [3:0] alias_raw;
  wire [3:0] alias_high;
  wire [3:0] alias_low;
  assign alias_high = alias_raw;
  late_alias_sink aliased (
      .p(halves_t'{alias_high, alias_low}),
      .value(value)
  );
  // Deliberately after the pattern: its proof must recheck the full alias inventory.
  alias alias_high = alias_low;

  // These are valid forward values, not writable inverse mappings.
  logic [6:0] a;
  logic b;
  logic [14:0] wider;
  wire [7:0] seen_named, seen_default, seen_constant, seen_cast, seen_func, seen_duplicate;
  function automatic logic [6:0] invert(input logic [6:0] x);
    return ~x;
  endfunction
  read_sink rn (
      .p(pair_t'{low: b, high: a}),
      .seen(seen_named)
  );
  read_sink rd (
      .p(pair_t'{high: a, default: 1'b1}),
      .seen(seen_default)
  );
  read_sink rc (
      .p(pair_t'{high: 7'h24, low: 1'b0}),
      .seen(seen_constant)
  );
  read_sink rt (
      .p(pair_t'{high: 7'(wider), low: b}),
      .seen(seen_cast)
  );
  read_sink rf (
      .p(pair_t'{high: invert(a), low: b}),
      .seen(seen_func)
  );
  read_sink rr (
      .p(pair_t'{high: {7{b}}, low: b}),
      .seen(seen_duplicate)
  );

  typedef struct packed {
    logic high;
    logic low;
  } bit_pair_t;
  logic [3:0] index_data;
  logic index_peer_value;
  int index_value;
  wire [3:0] index_net = index_data;
  wire index_peer = index_peer_value;
  wire [1:0] index_seen;
  function automatic int select_index(input int i);
    return i;
  endfunction
  bit_pair_read_sink runtime_select (
      .p(bit_pair_t'{index_net[select_index(index_value)], index_peer}),
      .seen(index_seen)
  );

  initial begin
    index_data = 4'b1010;
    index_peer_value = 1'b1;
    index_value = 0;
    resolved_ext_en = 0;
    value = 8'hb3;
    alias_raw = 4'h0;
    variable_h = 7'h12;
    variable_l = 0;
    a = 7'h53;
    b = 1;
    wider = 15'h1234;
    #1;
    `checkh(nh, 7'bzzzzzzz);
    `checkh(nl, 1'bz);
    `checkh(typed_high, 5'bzzzzz);
    `checkh(typed_low, 3'bzzz);
    `checkh({control_high, control_low}, value);
    `checkh({wide_selected[14:8], wide_selected[0]}, value);
    `checkh(counted, value);
    `checkh({ph, pl}, value);
    `checkh({selected[14:8], selected[0]}, value);
    `checkh(variable_h, 7'h12);
    `checkh(variable_l, 0);
    // A proved positional net destination still returns on this input formal.
    `checkh({mh, ml}, value);
    `checkh(seen_named, {a, b});
    `checkh(seen_default, {a, 1'b1});
    `checkh(seen_constant, 8'h48);
    `checkh(seen_cast, {wider[6:0], b});
    `checkh(seen_func, {7'h2c, b});
    `checkh(seen_duplicate, 8'hff);
    `checkh(alias_high, alias_raw);
    `checkh(alias_low, alias_raw);
    `checkh(index_seen, 2'b01);
    `checkh({resolved_high, resolved_low}, value);
    `checkh(resolved_pos_seen, value);
    `checkh(resolved_named_seen, value);
    `checkh(resolved_named_high, 7'bzzzzzzz);
    `checkh(resolved_named_low, 1'bz);
    resolved_ext_en = 1;
    index_peer_value = 1'b0;
    index_value = 1;
    value = 8'h64;
    alias_raw = 4'h9;
    a = 7'h12;
    b = 0;
    wider = 15'h1265;
    #1;
    `checkh(nh, 7'bzzzzzzz);
    `checkh(nl, 1'bz);
    `checkh(typed_high, 5'bzzzzz);
    `checkh(typed_low, 3'bzzz);
    `checkh({control_high, control_low}, value);
    `checkh({wide_selected[14:8], wide_selected[0]}, value);
    `checkh(counted, value);
    `checkh({ph, pl}, value);
    `checkh({selected[14:8], selected[0]}, value);
    // A proved positional net destination still returns on this input formal.
    `checkh({mh, ml}, value);
    `checkh(variable_h, 7'h12);
    `checkh(variable_l, 0);
    `checkh(seen_named, {a, b});
    `checkh(seen_default, {a, 1'b1});
    `checkh(seen_cast, {wider[6:0], b});
    `checkh(seen_func, {7'h6d, b});
    `checkh(seen_duplicate, 8'h00);
    `checkh(index_seen, 2'b10);
    `checkh({resolved_high, resolved_low}, value);
    `checkh(resolved_pos_seen, value);
    `checkh(resolved_named_seen, value);
    `checkh(resolved_named_high, 7'bzzzzzzz);
    `checkh(resolved_named_low, 1'bz);
    `checkh(alias_high, alias_raw);
    `checkh(alias_low, alias_raw);
    done = 1;
  end
endmodule

package bound_pattern_types;
  typedef struct packed {
    logic [6:0] tag;
    logic last;
  } payload_t;
  typedef struct packed {
    bit [6:0] tag;
    bit last;
  } bit_payload_t;
  typedef struct packed {
    logic high;
    logic low;
  } two_bits_t;
endpackage

interface bound_pattern_driver #(
    parameter int DW = 8
) (
    output wire [DW-1:0] data,
    input wire [DW-1:0] value
);
  assign data = value;
endinterface
interface bound_pattern_rv #(
    parameter type T = bound_pattern_types::payload_t
) (
    input wire [$bits(T)-1:0] data,
    input wire [$bits(T)-1:0] value
);
endinterface
bind bound_pattern_rv bound_pattern_driver #($bits(
    T
)) driver (
    .data(data),
    .value(value)
);

interface bound_pattern_harness (
    input wire [6:0] tag,
    input wire last,
    input wire [7:0] value
);
  bound_pattern_rv tx (
      .data(bound_pattern_types::payload_t'{tag, last}),
      .value(value)
  );
endinterface
module bound_pattern_dut (
    input wire [6:0] tag,
    input wire last,
    input wire [7:0] value,
    output wire [7:0] seen
);
  assign seen = {tag, last};
  bound_pattern_harness h (
      .tag(tag),
      .last(last),
      .value(value)
  );
endmodule

// Repeated NET bits and a two-state constructor are legal values but not typed NET bijections.
module duplicate_pattern_sink (
    input wire [7:0] p,
    input wire [7:0] value
);
endmodule
bind duplicate_pattern_sink bound_pattern_driver driver (
    .data(p),
    .value(value)
);
module bit_loss_pattern_sink (
    input wire [7:0] p,
    input wire [7:0] value
);
endmodule
bind bit_loss_pattern_sink bound_pattern_driver driver (
    .data(p),
    .value(value)
);
module negative_index_sink (
    input wire [1:0] p,
    input wire [1:0] value
);
endmodule
bind negative_index_sink bound_pattern_driver #(2) driver (
    .data(p),
    .value(value)
);

module wrapped_index_sink (
    input wire [1:0] p,
    input wire [1:0] value
);
endmodule
bind wrapped_index_sink bound_pattern_driver #(2) driver (.data(p), .value(value));

module negative_lsb_sink (
    input wire [1:0] p,
    input wire [1:0] value
);
endmodule
bind negative_lsb_sink bound_pattern_driver #(2) driver (.data(p), .value(value));

interface pattern_leaf_if;
  wire [6:0] tag;
endinterface
module xref_pattern_sink (
    input wire [7:0] p,
    input wire [7:0] value
);
endmodule
bind xref_pattern_sink bound_pattern_driver driver (
    .data(p),
    .value(value)
);
module pattern_views (
    pattern_leaf_if left,
    pattern_leaf_if right,
    input wire [7:0] value
);
  // Two interface port spellings resolve to the same NET in the owning instance.
  xref_pattern_sink sink (
      .p(bound_pattern_types::payload_t'{left.tag, right.tag[0]}),
      .value(value)
  );
endmodule

module bound_cases(output bit done);
  import bound_pattern_types::*;
  logic [7:0] value0;
  logic [7:0] value1;
  wire [7:0] seen0;
  wire [7:0] seen1;
  bound_pattern_dut d0 (
      .tag(),
      .last(),
      .value(value0),
      .seen(seen0)
  );
  bound_pattern_dut d1 (
      .tag(),
      .last(),
      .value(value1),
      .seen(seen1)
  );

  wire [6:0] repeated;
  wire [6:0] bit_tag;
  wire bit_last;
  // Separate formal declarations make each rejection independently observable.
  duplicate_pattern_sink duplicate_bits (
      .p(payload_t'{repeated, repeated[0]}),
      .value(value0)
  );
  bit_loss_pattern_sink bit_loss (
      .p(bit_payload_t'{bit_tag, bit_last}),
      .value(value1)
  );

  wire [2:-1] invalid_select;
  wire [2:-1] invalid_expression_select;
  wire [2:-1] valid_select;
  wire [2:-1] integer_select;
  wire invalid_peer, invalid_expression_peer, valid_peer, integer_peer;
  // A full-width index keeps its value, so it is out of range
  // verilator lint_off SELRANGE
  // verilator lint_off WIDTHTRUNC
  wrapped_index_sink wrapped_index (
      .p(two_bits_t'{invalid_select[64'hffff_ffff], invalid_peer}), .value(value0[1:0])
  );
  wrapped_index_sink wrapped_expression (
      .p(two_bits_t'{invalid_expression_select[(64'hffff_fffe + 64'd1)], invalid_expression_peer}),
      .value(value1[1:0])
  );
  // verilator lint_on WIDTHTRUNC
  // verilator lint_on SELRANGE
  // A 32-bit index is an integer, so this selects bit -1
  negative_lsb_sink integer_negative (
      .p(two_bits_t'{integer_select[32'hffff_ffff], integer_peer}), .value({value0[6], value1[6]})
  );
  negative_lsb_sink valid_negative (
      .p(two_bits_t'{valid_select[-1], valid_peer}), .value({value0[7], value1[7]})
  );

  logic [6:0] interface_raw;
  logic [3:0] negative_raw;
  logic low_raw;
  wire [3:0] n;
  wire low;
  assign n = negative_raw;
  assign low = low_raw;
  // verilator lint_off SELRANGE
  negative_index_sink negative (
      .p(two_bits_t'{n[-1], low}),
      .value(2'b10)
  );
  // verilator lint_on SELRANGE
  pattern_leaf_if shared ();
  assign shared.tag = interface_raw;
  pattern_views views (
      .left(shared),
      .right(shared),
      .value(value0)
  );

  initial begin
    interface_raw = 7'h00;
    negative_raw = 4'h0;
    low_raw = 0;
    value0 = 8'hab;
    value1 = 8'h52;
    #1;
    `checkh(seen0, value0);
    `checkh(seen1, value1);
    `checkh(d0.h.tx.data, value0);
    `checkh(d1.h.tx.data, value1);
    `checkh(valid_select[-1], value0[7]);
    `checkh(valid_peer, value1[7]);
    `checkh(integer_select[-1], value0[6]);
    `checkh(integer_peer, value1[6]);
    `checkh(invalid_select[-1], 1'bz);
    `checkh(invalid_peer, 1'bz);
    `checkh(invalid_expression_select[-1], 1'bz);
    `checkh(invalid_expression_peer, 1'bz);
    `checkh(repeated, 7'bzzzzzzz);
    // Component checks preserve the ALL-Z predicate without a concat enable expression.
    `checkh(bit_tag, 7'bzzzzzzz);
    `checkh(bit_last, 1'bz);
    `checkh(shared.tag, interface_raw);
    `checkh(n, negative_raw);
    `checkh(low, low_raw);
    value0 = 8'h36;
    negative_raw = 4'h9;
    low_raw = 1;
    interface_raw = 7'h35;
    value1 = 8'hc9;
    #1;
    `checkh(seen0, value0);
    `checkh(seen1, value1);
    `checkh(valid_select[-1], value0[7]);
    `checkh(valid_peer, value1[7]);
    `checkh(integer_select[-1], value0[6]);
    `checkh(integer_peer, value1[6]);
    `checkh(invalid_select[-1], 1'bz);
    `checkh(invalid_peer, 1'bz);
    `checkh(invalid_expression_select[-1], 1'bz);
    `checkh(invalid_expression_peer, 1'bz);
    `checkh(repeated, 7'bzzzzzzz);
    // Component checks preserve the ALL-Z predicate without a concat enable expression.
    `checkh(bit_tag, 7'bzzzzzzz);
    `checkh(bit_last, 1'bz);
    `checkh(shared.tag, interface_raw);
    `checkh(n, negative_raw);
    `checkh(low, low_raw);
    done = 1;
  end
endmodule

package leaf_types;
  typedef struct packed {
    logic [3:0] high;
    logic [3:0] low;
  } halves_t;
endpackage

interface leaf_driver (
    output wire [7:0] p,
    input wire [7:0] value
);
  assign p = value;
endinterface

module packed_backing_sink (
    input wire [7:0] p,
    input wire [7:0] value
);
endmodule
bind packed_backing_sink leaf_driver driver (
    .p(p),
    .value(value)
);

module basic_backing_sink (
    input wire [7:0] p,
    input wire [7:0] value
);
endmodule
bind basic_backing_sink leaf_driver driver (
    .p(p),
    .value(value)
);

module passive_leaf_sink (
    input wire [7:0] p,
    output wire [7:0] seen
);
  assign seen = p;
endmodule

module leaf_cases(output bit done);
  import leaf_types::*;

  logic [7:0] value;
  wire [1:0][3:0] packed_net;
  packed_backing_sink negative (
      .p(halves_t'{packed_net[1], packed_net[0]}),
      .value(value)
  );

  wire [3:0] basic_high;
  wire [3:0] basic_low;
  basic_backing_sink positive (
      .p(halves_t'{basic_high, basic_low}),
      .value(value)
  );

  logic [7:0] forward_value;
  wire [1:0][3:0] forward_net;
  assign forward_net = forward_value;
  wire [7:0] seen;
  passive_leaf_sink forward_reader (
      .p(halves_t'{high: forward_net[1], low: forward_net[0]}),
      .seen(seen)
  );

  initial begin
    for (int step = 0; step < 4; ++step) begin
      value = 8'ha3 ^ {8{step[0]}} ^ (8'(step >> 1) << 4);
      forward_value = 8'h5c ^ {8{step[0]}} ^ 8'(step >> 1);
      #1;
      // Scalar members do not make the packed-array backing declaration scalar.
      `checkh(packed_net[1], 4'bzzzz);
      `checkh(packed_net[0], 4'bzzzz);
      // Separate basic-net leaves must still receive the bound output driver.
      `checkh(basic_high, value[7:4]);
      `checkh(basic_low, value[3:0]);
      `checkh(seen, forward_value);
      `checkh(forward_net[1], forward_value[7:4]);
      `checkh(forward_net[0], forward_value[3:0]);
    end
    done = 1;
  end
endmodule

package member_types;
  typedef struct packed {logic [3:0] n;} inner_t;
  typedef struct packed {
    inner_t m;
    logic tail;
  } outer_t;
  typedef struct packed {
    logic [3:0] high;
    logic low;
  } basic_t;
endpackage

interface member_driver (
    output wire [4:0] p,
    input wire [4:0] value
);
  assign p = value;
endinterface

// Each inverse eligibility check has its own formal declaration.
module nested_member_sink (
    input wire [4:0] p,
    input wire [4:0] value
);
endmodule
bind nested_member_sink member_driver driver (
    .p(p),
    .value(value)
);

module basic_member_sink (
    input wire [4:0] p,
    input wire [4:0] value
);
endmodule
bind basic_member_sink member_driver driver (
    .p(p),
    .value(value)
);

module passive_member_sink (
    input wire [4:0] p,
    output wire [4:0] seen
);
  assign seen = p;
endmodule

module member_cases(output bit done);
  import member_types::*;

  logic [4:0] value;
  wire [3:0] nested_high;
  wire nested_low;
  nested_member_sink negative (
      .p(outer_t'{nested_high, nested_low}),
      .value(value)
  );

  wire [3:0] basic_high;
  wire basic_low;
  basic_member_sink positive (
      .p(basic_t'{basic_high, basic_low}),
      .value(value)
  );

  logic [4:0] forward_value;
  wire [3:0] forward_high;
  wire forward_low;
  assign forward_high = forward_value[4:1];
  assign forward_low = forward_value[0];
  wire [4:0] seen;
  passive_member_sink forward_reader (
      .p(outer_t'{m: forward_high, tail: forward_low}),
      .seen(seen)
  );

  initial begin
    for (int step = 0; step < 4; ++step) begin
      value = 5'h13 ^ {5{step[0]}} ^ 5'(step >> 1);
      forward_value = 5'h0c ^ {5{step[0]}} ^ (5'(step >> 1) << 1);
      #1;
      // A nested member is a legal forward value but not an admitted inverse leaf.
      `checkh(nested_high, 4'bzzzz);
      `checkh(nested_low, 1'bz);
      // This independent positive fails if no port coercion is exercised.
      `checkh(basic_high, value[4:1]);
      `checkh(basic_low, value[0]);
      `checkh(seen, forward_value);
      `checkh(forward_high, forward_value[4:1]);
      `checkh(forward_low, forward_value[0]);
    end
    done = 1;
  end
endmodule

module t;
  wire [3:0] done;
  pattern_cases patterns (.done(done[0]));
  bound_cases bounds (.done(done[1]));
  leaf_cases leaves (.done(done[2]));
  member_cases members (.done(done[3]));
  initial begin
    wait (&done);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
