// DESCRIPTION: Verilator: Test constant packed select positions at runtime
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// A nonblocking write outside its storage in a package task, which is widthed from a module
package nonblocking_pkg;
  logic [7:0] pkg_bits;
  task automatic pkg_write();
    // verilator lint_off SELRANGE
    pkg_bits[9] <= 1'b1;
    {pkg_bits[9], pkg_bits[1]} <= 2'b01;
    // verilator lint_on SELRANGE
  endtask
endpackage

// Defined after the module that calls its method
typedef class nonblocking_cls;

module t;
  bit clk = 0;
  always #1 clk = ~clk;
  int cycle = 0;
  bit [63:0] crc = 64'h5aef0c8d_d70a4497;
  always @(posedge clk) begin
    crc <= {crc[62:0], crc[63] ^ crc[2] ^ crc[0]};
    if (cycle == 9) begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
    cycle <= cycle + 1;
  end

  // Adjacent selects of one source merge only when both are within it
  always @(posedge clk) begin
    automatic logic [4:0] source = crc[4:0];
    automatic logic [7:0] neg_source = crc[15:8];
    automatic logic [3:0] adjacent, partial, negative;
    adjacent = {source[2+:2], source[0+:2]};
    // verilator lint_off SELRANGE
    partial = {source[4+:2], source[2+:2]};
    negative = {neg_source[2:1], neg_source[0-:2]};
    // verilator lint_on SELRANGE
    `checkh(adjacent, source[3:0]);
    `checkh(partial[2:0], source[4:2]);
    `checkh(negative[3:1], neg_source[2:0]);
  end

  // A constant position outside the storage is not wrapped into a valid element; the bits
  // of a partly outside read beyond the storage are 0 in a 2-state vector
  always @(posedge clk) begin
    automatic bit [7:0] bits = crc[7:0];
    automatic bit [1:0][31:0] words = {crc[63:32], crc[31:0]};
    automatic bit [8:1] offset_bits = crc[7:0];
    // verilator lint_off ASCRANGE
    automatic bit [0:7] up_bits = crc[7:0];
    // verilator lint_on ASCRANGE
    automatic bit [3:0] narrow_plus, narrow_range;
    // verilator lint_off SELRANGE
    // verilator lint_off WIDTH
    `checkh(bits[9], 1'b0);
    `checkh(bits[-1], 1'b0);
    `checkh(words[2], 32'h0);
    `checkh(offset_bits[0], 1'b0);
    `checkh(offset_bits[9], 1'b0);
    `checkh(up_bits[8], 1'b0);
    `checkh(bits[6+:4], {2'b00, bits[7:6]});
    `checkh(bits[1-:4], {bits[1:0], 2'b00});
    // A narrow signed position keeps its sign
    narrow_plus = bits[2'sb11+:4];
    narrow_range = bits[2'sb01:2'sb11];
    `checkh(narrow_plus, {bits[2:0], 1'b0});
    `checkh(narrow_range[2:0], {bits[1:0], 1'b0});
    // verilator lint_on WIDTH
    // verilator lint_on SELRANGE
  end

  // Constant writes outside the storage change nothing; a partly outside write changes only
  // the bits within the storage, from the corresponding bits of its value
  typedef struct packed {
    bit high;
    bit low;
  } pair_t;
  int calls = 0;
  function automatic bit [1:0] value();
    ++calls;
    return 2'b10;
  endfunction
  task automatic write_two(output bit [1:0] o);
    o = 2'b11;
  endtask
  always @(posedge clk) begin
    automatic bit [7:0] bits = crc[7:0];
    automatic bit [1:0][31:0] words = {crc[63:32], crc[31:0]};
    automatic bit [8:1] offset_bits = crc[7:0];
    // verilator lint_off ASCRANGE
    automatic bit [0:7] up_bits = crc[7:0];
    // verilator lint_on ASCRANGE
    automatic bit [7:0] low, high, through, concat, out;
    automatic bit [3:0] other;
    automatic pair_t [1:0] pairs = '0;
    automatic bit pair_other = 1'b0;
    automatic int calls_before = calls;
    // verilator lint_off SELRANGE
    bits[9] = 1'b1;
    words[2] = 32'hffff_ffff;
    offset_bits[0] = 1'b0;
    up_bits[8] = 1'b0;
    low = 8'h00;
    low[0-:2] = 2'b10;
    high = 8'h00;
    high[7+:2] = 2'b01;
    through = 8'h00;
    through[0-:2] = value();
    concat = 8'h00;
    {other, concat[0-:2]} = 6'b0101_10;
    out = 8'h00;
    write_two(out[7+:2]);
    write_two(out[9+:2]);
    {pairs[2].low, pair_other} = 2'b01;
    // verilator lint_on SELRANGE
    `checkh(bits, crc[7:0]);
    `checkh(words, {crc[63:32], crc[31:0]});
    `checkh(offset_bits, crc[7:0]);
    `checkh(up_bits, crc[7:0]);
    `checkh(low, 8'h01);
    `checkh(high, 8'h80);
    `checkh(through, 8'h01);
    `checkh(calls, calls_before + 1);
    `checkh(concat, 8'h01);
    `checkh(other, 4'b0101);
    `checkh(out, 8'h80);
    `checkh(pairs, 4'h0);
    `checkh(pair_other, 1'b1);
  end
  // Likewise for an output port connection
  wire [7:0] port_bits;
  // verilator lint_off SELRANGE
  sub_out u_outside (.o(port_bits[9+:2]));
  sub_out u_partial (.o(port_bits[7+:2]));
  // verilator lint_on SELRANGE
  always @(posedge clk) if (cycle == 2) `checkh(port_bits[7], 1'b1);

  // The value of a partly outside write is converted as for the whole destination, then its
  // bits beyond the storage are dropped
  always @(posedge clk) begin
    automatic bit [7:0] truncated, pattern, filled, streamed;
    automatic bit [3:0] nibble = crc[3:0];
    // verilator lint_off SELRANGE
    // verilator lint_off WIDTH
    truncated = 8'h00;
    truncated[-1+:4] = {4'h0, nibble};
    pattern = 8'h00;
    pattern[0-:2] = '{nibble[0], 1'b0};
    filled = 8'h00;
    filled[-1+:4] = '{default: 1'b1};
    streamed = 8'h00;
    streamed[-1+:8] = {<<{nibble}};
    // verilator lint_on WIDTH
    // verilator lint_on SELRANGE
    `checkh(truncated, {5'h0, nibble[3:1]});
    `checkh(pattern, {7'h0, nibble[0]});
    `checkh(filled, 8'h07);
    // A stream is left-aligned in the whole destination (IEEE 1800-2023 11.4.14)
    `checkh(streamed, {1'b0, nibble[0], nibble[1], nibble[2], nibble[3], 3'b000});
  end

  // The receiver of a wholly outside read, and the address and value of a wholly or partly
  // outside write, are evaluated once
  int receiver_calls = 0, address_calls = 0, value_calls = 0;
  function automatic logic [7:0] receiver();
    ++receiver_calls;
    return crc[7:0];
  endfunction
  function automatic int address();
    ++address_calls;
    return 1;
  endfunction
  function automatic logic written_value();
    ++value_calls;
    return 1'b1;
  endfunction
  typedef struct {logic [3:0] f;} field_t;
  always @(posedge clk) begin
    automatic logic [3:0] rows[2] = '{4'h7, 4'ha};
    automatic logic [1:0][3:0] packed_rows[2] = '{8'h12, 8'h34};
    automatic field_t fields[2] = '{'{f: 4'h5}, '{f: 4'h6}};
    automatic int receivers = receiver_calls, addresses = address_calls, values = value_calls;
    automatic logic outside;
    // verilator lint_off SELRANGE
    outside = {receiver()}[9];
    rows[address()][9] = written_value();
    rows[address()][-1+:2] = {written_value(), 1'b0};
    // Through a packed element, and through a member of an unpacked structure
    packed_rows[address()][1][9] = written_value();
    fields[address()].f[9] = written_value();
    // verilator lint_on SELRANGE
    `checkh(receiver_calls, receivers + 1);
    `checkh(address_calls, addresses + 4);
    `checkh(value_calls, values + 4);
    `checkh(rows[0], 4'h7);
    `checkh(rows[1], 4'hb);
    `checkh(packed_rows[1], 8'h34);
    `checkh(fields[1].f, 4'h6);
  end

  // An output argument of a function called in a position of a destination is written by
  // that call, not by the assignment, so its address is evaluated only when the call is
  int branch_calls = 0;
  function automatic bit branch_address();
    ++branch_calls;
    return 1'b0;
  endfunction
  int slot_calls = 0;
  function automatic bit branch_slot(output logic discard);
    ++slot_calls;
    discard = 1'b1;
    return 1'b1;
  endfunction
  function automatic bit branch_pair(output logic [1:0] discard);
    discard = 2'b11;
    return 1'b1;
  endfunction
  initial begin
    automatic logic [3:0] branch_rows[2];
    automatic logic [1:0] branch_dest;
    for (int choose = 0; choose < 2; ++choose) begin
      branch_calls = 0;
      branch_dest = '0;
      branch_rows = '{4'h4, 4'h4};
      // verilator lint_off SELRANGE
      branch_dest[choose[0] ? branch_slot(branch_rows[branch_address()][9]) : 1'b0] = 1'b1;
      branch_dest[choose[0] ? branch_pair(branch_rows[branch_address()][-1+:2]) : 1'b0] = 1'b1;
      // verilator lint_on SELRANGE
      `checkh(branch_calls, 2 * choose);
      `checkh(branch_dest, choose[0] ? 2'b10 : 2'b01);
      `checkh(branch_rows[0], choose[0] ? 4'h5 : 4'h4);
      `checkh(branch_rows[1], 4'h4);
    end
    // Likewise with an intra-assignment delay, with an address without side effects
    for (int choose = 0; choose < 2; ++choose) begin
      automatic time start = $time;
      slot_calls = 0;
      branch_dest = '0;
      branch_rows = '{4'h4, 4'h4};
      // verilator lint_off SELRANGE
      branch_dest[choose[0] ? branch_slot(branch_rows[0][9]) : 1'b0] = #1 1'b1;
      // verilator lint_on SELRANGE
      `checkh($time - start, 1);
      `checkh(slot_calls, choose);
      `checkh(branch_dest, choose[0] ? 2'b10 : 2'b01);
      `checkh(branch_rows[0], 4'h4);
    end
  end

  // A force or release changes only the bits within the net
  wire [7:0] forced_net = crc[7:0];
  initial begin
    #3;
    // verilator lint_off SELRANGE
    force forced_net[-1+:2] = 2'b11;
    force forced_net[9] = 1'b1;
    #1;
    `checkh(forced_net[0], 1'b1);
    `checkh(forced_net[7:1], crc[7:1]);
    release forced_net[-1+:2];
    release forced_net[9];
    // verilator lint_on SELRANGE
    #1;
    `checkh(forced_net, crc[7:0]);
  end

  // A part of a forced or released concatenation outside the net changes nothing; the other
  // parts are forced from their own bits of the value
  wire [7:0] concat_net = 8'h08;
  int forced_calls = 0;
  function automatic logic forced_value();
    ++forced_calls;
    return 1'b1;
  endfunction
  wire [3:0][1:0] nested_net = '0;
  initial begin
    #3;
    // verilator lint_off SELRANGE
    force {concat_net[9], concat_net[1], concat_net[0]} = 3'b101;
    #1;
    `checkh(concat_net, 8'h09);
    release {concat_net[9], concat_net[1], concat_net[0]};
    #1;
    `checkh(concat_net, 8'h08);
    force {concat_net[2], concat_net[9], concat_net[0]} = 3'b101;
    #1;
    `checkh(concat_net, 8'h0d);
    release {concat_net[2], concat_net[9], concat_net[0]};
    #1;
    `checkh(concat_net, 8'h08);
    force {concat_net[-1+:2], concat_net[3]} = 3'b110;
    #1;
    `checkh(concat_net, 8'h01);
    // A release of a part without storage releases the other parts
    release {concat_net[8], concat_net[0], concat_net[3]};
    #1;
    `checkh(concat_net, 8'h08);
    force {concat_net[9], concat_net[8]} = 2'b11;
    release {concat_net[9], concat_net[8]};
    // The value of a removed force is still evaluated once
    force concat_net[9] = forced_value();
    `checkh(forced_calls, 1);
    // A select of an element outside the net, within a part, has no storage bits either
    force nested_net[5][0] = 1'b1;
    release nested_net[5][0];
    force {nested_net[5][1:0], nested_net[0][0]} = 3'b111;
    #1;
    `checkh(nested_net, 8'h01);
    release {nested_net[5][1:0], nested_net[0][0]};
    #1;
    `checkh(nested_net, 8'h00);
    // verilator lint_on SELRANGE
    #1;
    `checkh(concat_net, 8'h08);
  end

  // A wholly outside blocking write with an intra-assignment delay evaluates its value when
  // the statement starts and its address after the delay (IEEE 1800-2023 9.4.5)
  int timed_address_calls = 0;
  int timed_value_calls = 0;
  time timed_address_time = 0;
  time timed_value_time = 0;
  function automatic int timed_address();
    ++timed_address_calls;
    timed_address_time = $time;
    return 1;
  endfunction
  function automatic logic timed_value();
    ++timed_value_calls;
    timed_value_time = $time;
    return 1'b1;
  endfunction
  initial begin
    automatic logic [3:0] timed_rows[2] = '{4'h3, 4'h5};
    #3;
    // verilator lint_off SELRANGE
    timed_rows[bit'(timed_address())][9] = #2 timed_value();
    // verilator lint_on SELRANGE
    `checkh(timed_address_calls, 1);
    `checkh(timed_value_calls, 1);
    `checkh(timed_value_time, 3);
    `checkh(timed_address_time, 5);
    `checkh(timed_rows[0], 4'h3);
    `checkh(timed_rows[1], 4'h5);
  end

  // The address of a wholly outside write to an element of a queue, dynamic or associative
  // array is evaluated without its writable lookup, so no element is created or written
  int index_calls = 0;
  function automatic int container_index();
    ++index_calls;
    return 0;
  endfunction
  initial begin
    automatic logic [3:0] empty_queue[$];
    automatic logic [3:0] queue[$] = '{4'h5};
    automatic logic [3:0] dynamic[] = new[2];
    automatic logic [3:0] assoc[int];
    automatic logic [3:0] fixed[2] = '{4'h1, 4'h2};
    dynamic[0] = 4'h3;
    #3;
    // verilator lint_off SELRANGE
    empty_queue[container_index()][9] = 1'b1;
    `checkh(index_calls, 1);
    `checkh(empty_queue.size(), 0);
    queue[container_index()][9] = 1'b1;
    `checkh(index_calls, 2);
    `checkh(queue.size(), 1);
    `checkh(queue[0], 4'h5);
    dynamic[container_index()][9] = 1'b1;
    `checkh(index_calls, 3);
    `checkh(dynamic.size(), 2);
    `checkh(dynamic[0], 4'h3);
    assoc[container_index()][9] = 1'b1;
    `checkh(index_calls, 4);
    `checkh(assoc.size(), 0);
    fixed[container_index()][9] = 1'b1;
    `checkh(index_calls, 5);
    `checkh(fixed[0], 4'h1);
    `checkh(fixed[1], 4'h2);
    empty_queue[container_index()][9] = #1 1'b1;
    // verilator lint_on SELRANGE
    `checkh(index_calls, 6);
    `checkh(empty_queue.size(), 0);
  end

  // A nonblocking write may not update an automatic variable, including an element of an
  // automatic fixed-size array, or an element of a dynamically sized array
  // (IEEE 1800-2023 10.4.2); this one updates a static fixed-size array
  logic [3:0] nonblocking_fixed[2] = '{4'h6, 4'h9};
  // Likewise with positions without side effects, including a key that does not exist
  initial begin
    automatic logic [3:0] empty_queue[$];
    automatic logic [3:0] queue[$] = '{4'h5};
    automatic logic [3:0] dynamic[] = new[1];
    automatic logic [3:0] assoc[int];
    automatic int position = 0;
    dynamic[0] = 4'h3;
    assoc[1] = 4'h7;
    #3;
    // verilator lint_off SELRANGE
    empty_queue[0][9] = 1'b1;
    empty_queue[position][9] = 1'b1;
    queue[$][9] = 1'b1;
    nonblocking_fixed[0][9] <= 1'b1;
    dynamic[0][9] = 1'b1;
    dynamic[position][9] = 1'b1;
    assoc[1][9] = 1'b1;
    assoc[2][9] = 1'b1;
    empty_queue[0][9] = #1 1'b1;
    // verilator lint_on SELRANGE
    #1;
    `checkh(empty_queue.size(), 0);
    `checkh(queue.size(), 1);
    `checkh(queue[0], 4'h5);
    `checkh(dynamic.size(), 1);
    `checkh(dynamic[0], 4'h3);
    `checkh(assoc.size(), 1);
    `checkh(assoc[1], 4'h7);
    `checkh(nonblocking_fixed[0], 4'h6);
  end

  // A nonblocking write in a task or function places a part outside its storage in a static
  // temporary of that task or function, as a nonblocking assignment may not write an
  // automatic variable (IEEE 1800-2023 6.21, 10.4.2)
  logic [7:0] nonblocking_bits = 8'h00;
  nonblocking_cls nonblocking_obj = new;
  task automatic nonblocking_task();
    // verilator lint_off SELRANGE
    nonblocking_bits[9] <= 1'b1;
    // verilator lint_on SELRANGE
  endtask
  function automatic void nonblocking_function();
    // verilator lint_off SELRANGE
    {nonblocking_bits[9], nonblocking_bits[0]} <= 2'b01;
    // verilator lint_on SELRANGE
  endfunction
  initial begin
    #3;
    nonblocking_task();
    nonblocking_pkg::pkg_bits = 8'h00;
    nonblocking_pkg::pkg_write();
    nonblocking_obj.method_write();
    nonblocking_function();
    #1;
    `checkh(nonblocking_bits, 8'h01);
    `checkh(nonblocking_pkg::pkg_bits, 8'h02);
    `checkh(nonblocking_obj.obj_bits, 8'h01);
  end

  // A part of a concatenated destination outside its storage takes its bits of the value
  initial begin
    automatic logic [7:0] parts = 8'h00;
    #3;
    // verilator lint_off SELRANGE
    {parts[9], parts[1], parts[0]} = 3'b101;
    // verilator lint_on SELRANGE
    `checkh(parts, 8'h01);
  end

  // Likewise for a streaming concatenation as an assignment target, also with braces within it
  initial begin
    automatic logic [7:0] stream_bits = '0;
    automatic logic stream_low = 1'b0;
    automatic logic [1:0] stream_pair = '0;
    automatic logic [3:0] stream_nibble = '0;
    // verilator lint_off SELRANGE
    {>>{stream_bits[9], stream_low}} = 2'b01;
    `checkh(stream_low, 1'b1);
    {<<{stream_pair, stream_bits[10]}} = 3'b011;
    `checkh(stream_pair, 2'b11);
    {>>{{stream_bits[9], stream_nibble[0]}, stream_low}} = 3'b110;
    `checkh(stream_nibble, 4'h1);
    `checkh(stream_low, 1'b0);
    {>>{stream_bits[-1+:2], stream_low}} = 3'b111;
    // verilator lint_on SELRANGE
    `checkh(stream_bits, 8'h01);
    `checkh(stream_low, 1'b1);
  end

  // A wide negative constant position partly within an operand reads its in-range bits
  always @(posedge clk) begin
    automatic bit [7:0] bits = crc[7:0];
    // verilator lint_off SELRANGE
    // verilator lint_off WIDTH
    `checkh(bits[65'sh1_ffff_ffff_ffff_ffff+:2], {bits[0], 1'b0});
    // verilator lint_on WIDTH
    // verilator lint_on SELRANGE
  end

  // A 32-bit position is a signed integer whether it is constant or not
  always @(posedge clk) begin
    automatic logic [15:-16] neg16 = crc[31:0];
    automatic logic [2:-1] neg1 = crc[35:32];
    automatic logic [31:0] flat16 = crc[31:0];
    automatic logic [3:0] flat1 = crc[35:32];
    automatic int unsigned k = 32'(cycle[1:0]);
    automatic logic [31:0] index16 = 32'hffff_fff0 + k;
    automatic int unsigned j = 32'(cycle[0]);
    automatic logic [31:0] index1 = 32'hffff_ffff + j;
    automatic bit [2:-1] neg1_bits = crc[35:32];
    `checkh(neg16[32'hffff_fff0], flat16[0]);
    `checkh(neg16[32'hffff_fff0+:2], flat16[1:0]);
    `checkh(neg1[32'hffff_ffff], flat1[0]);
    `checkh(neg16[index16], flat16[k]);
    `checkh(neg16[index16+:2], flat16[k+:2]);
    `checkh(neg1[index1], flat1[j]);
    // A wider constant position keeps its full value, so it is out of range
    // verilator lint_off WIDTHTRUNC
    // verilator lint_off SELRANGE
    `checkh(neg1_bits[64'hffff_ffff], 1'b0);
    // verilator lint_on SELRANGE
    // verilator lint_on WIDTHTRUNC
  end
endmodule

// The same in a class method, declared after the module that calls it
class nonblocking_cls;
  logic [7:0] obj_bits = 8'h00;
  function void method_write();
    // verilator lint_off SELRANGE
    {obj_bits[9], obj_bits[0]} <= 2'b01;
    // verilator lint_on SELRANGE
  endfunction
endclass

module sub_out (
    output logic [1:0] o
);
  assign o = 2'b11;
endmodule
