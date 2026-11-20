// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t (
    input logic [2:-1] bits_in,
    output logic [2:0] result,
    output logic [1:0] far_slice
);
  // A 32-bit position is the integer -1, which is within the storage
  assign result[2] = bits_in[32'hffff_ffff];
  // A wider position keeps its full value
  assign result[1] = bits_in[64'hffff_ffff +: 1];
  assign result[0] = bits_in[64'hffff_ffff -: 1];
  assign far_slice = bits_in[32'sh7fff_ffff +: 2];

  logic [63:0] wide_index;
  logic [1:0] narrow_index;
  logic [1:0] wide_result;
  logic [4:0] narrow_source;
  logic narrow_result;
  // Report the authored width, not the storage offset's carry/stride width.
  assign wide_result[0] = bits_in[wide_index];
  assign wide_result[1] = bits_in[wide_index+:1];
  assign narrow_result = narrow_source[narrow_index-:1];

  // A sized constant index is diagnosed where it is the bit offset itself
  logic [7:0] down;
  logic [8:1] offset_down;
  // verilator lint_off ASCRANGE
  logic [0:7] up;
  // verilator lint_on ASCRANGE
  logic [3:0][1:0] elements;
  logic [10:0] constant_result;
  assign constant_result[0] = down[4'd3];
  assign constant_result[1] = down[2'd3];
  assign constant_result[3:2] = down[4'd3+:2];
  assign constant_result[4] = down[4'd3-:1];
  assign constant_result[6:5] = down[4'd3:4'd2];
  assign constant_result[7] = down[3'd3];
  assign constant_result[8] = offset_down[4'd3];
  assign constant_result[9] = up[4'd3];
  assign constant_result[10] = elements[3'd1][0];

  // A wide constant index keeps its width diagnostic, inside or outside the range
  logic [15:8] high;
  logic [1:0] wide_constant;
  assign wide_constant[0] = down[64'd9];
  assign wide_constant[1] = high[64'd9];

  // Out-of-range positions are reported in declared coordinates
  logic [-3:-6] negative_range;
  logic [3:0] declared;
  assign declared[0] = offset_down[9];
  assign declared[1] = negative_range[-7];
  assign declared[3:2] = down[0-:2];

  // An unknown count or endpoint is an error
  logic [3:0] unknown_count;
  logic [1:0] unknown_endpoint;
  assign unknown_count = down[0+:4'bx];
  assign unknown_endpoint = down[3:2'bxx];

  // Out-of-range positions are reported in declared coordinates, also beyond the top
  logic [45:40] offset_six;
  logic [6:0] beyond;
  assign beyond[3:0] = offset_six[44+:4];
  assign beyond[6:4] = offset_down[10:8];

  // The value of a partly outside write keeps its width diagnostic
  logic [7:0] written;
  always_comb begin
    written = '0;
    written[-1+:4] = 8'hff;
  end

  // A partly outside write in a combinational concatenation leaves no latch
  logic [7:0] combined;
  logic combined_low;
  always_comb begin
    combined = '0;
    combined_low = 1'b0;
    if (narrow_index[0]) {combined[-1+:2], combined_low} = 3'b111;
  end

  // The index width is checked at the type of the constant position as written, also when it
  // is computed, and for an ascending range at its right index, from which the offset is computed
  logic [15:8] width_offset;
  // verilator lint_off ASCRANGE
  logic [0:7] width_up;
  // verilator lint_on ASCRANGE
  function automatic logic [63:0] wide_nine();
    return 64'd9;
  endfunction
  logic [1:0] width_direct, width_computed, width_function, width_literal;
  logic [1:0] width_up_both, width_up_left, width_up_right, width_up_computed;
  assign width_direct = width_offset[64'd9+:2];
  assign width_computed = width_offset[(64'd8+64'd1)+:2];
  assign width_function = width_offset[wide_nine()+:2];
  assign width_literal = width_offset[9+:2];  // No warning: a 32-bit position
  assign width_up_both = width_up[64'd2:64'd3];
  assign width_up_left = width_up[64'd2:3];  // No warning: the right index is 32 bits
  assign width_up_right = width_up[2:64'd3];
  assign width_up_computed = width_up[2:(64'd2+64'd1)];

  // A partly outside select in an alias or a clocking item is unsupported
  wire [7:0] aliased;
  wire [1:0] alias_other;
  alias aliased[0-:2] = alias_other;
  logic clocked_clk;
  logic [7:0] clocked;
  clocking clocked_cb @(posedge clocked_clk);
    output clocked_out = clocked[0-:2];
  endclocking

  // An impure value forced on separate parts of a concatenation is unsupported
  wire [7:0] forced_parts;
  int force_calls;
  function automatic logic [2:0] force_value();
    ++force_calls;
    return 3'b101;
  endfunction
  initial force {forced_parts[1], forced_parts[9], forced_parts[0]} = force_value();

  // A wholly outside write whose destination has side effects outside its positions is
  // unsupported, as its address cannot be evaluated without it
  class side_holder;
    logic [3:0] bits;
  endclass
  side_holder side_object = new;
  int side_calls;
  function automatic side_holder side_get();
    ++side_calls;
    return side_object;
  endfunction
  initial side_get().bits[9] = 1'b1;

  // A position wider than an int is reported with its sign, and endpoints wider than an int
  // give a select of their shape
  logic far_negative;
  logic [1:0] far_element;
  assign far_negative = down[-64'sd2147483649];
  assign far_element = elements[64'sh8000_0000:64'sh8000_0000];

  // A wholly outside output argument of a function called in an index of a destination with
  // an intra-assignment delay is unsupported when its address has side effects
  logic [3:0] delayed_rows[2];
  logic [1:0] delayed_dest;
  function automatic bit delayed_address();
    ++side_calls;
    return 1'b0;
  endfunction
  function automatic bit delayed_slot(output logic discard);
    discard = 1'b1;
    return 1'b1;
  endfunction
  initial delayed_dest[delayed_slot(delayed_rows[delayed_address()][9])] = #1 1'b1;

  // As is one in a destination with other parts and an intra-assignment delay, as its address
  // would be evaluated after the other parts are written
  logic delayed_live;
  logic [3:0][1:0] delayed_pairs[2];
  delayed_sub delayed_inst ();
  initial begin
    {delayed_rows[delayed_address()][9], delayed_live} = #1 2'b01;
    {>>{delayed_rows[delayed_address()][9], delayed_live}} = #1 2'b01;
    {>>{{delayed_rows[delayed_address()][9]}, delayed_live}} = #1 2'b01;
    {delayed_pairs[delayed_address()][5][0], delayed_live} = #1 2'b01;
    // Also when the other part is a hierarchical reference or a class property
    {delayed_rows[delayed_address()][9], delayed_inst.live} = #1 2'b01;
  end
  class delayed_holder;
    logic live;
    logic [3:0] rows[2];
    int calls;
    function automatic bit address();
      ++calls;
      return 1'b0;
    endfunction
    task write();
      {rows[address()][9], this.live} = #1 2'b01;
    endtask
  endclass
  delayed_holder delayed_object = new;
  initial {delayed_rows[delayed_address()][9], delayed_object.live} = #1 2'b01;

  // A partly outside select connected to an inout port is unsupported
  wire [7:0] bidir;
  sub_inout u_inout (.p(bidir[0-:2]));
endmodule

module delayed_sub;
  logic live;
endmodule

module sub_inout (
    inout wire [1:0] p
);
endmodule
