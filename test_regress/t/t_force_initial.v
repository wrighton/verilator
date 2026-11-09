// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2025 Antmicro
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0)
// verilog_format: on

typedef struct packed {
  logic [31:0] count;
  logic [31:0] bytes;
} force_packed_item_t;

interface force_ifc;
  logic [3:0] sig;
  logic [127:0] wide;
  logic [15:0][31:0] words;
  logic [127:0][15:0] halfwords;
  force_packed_item_t [2:1][7:3] records;
  logic [63:0] counter;
  logic [95:0] unforced_wide;
  real unforced_real;
endinterface

class ForceReader;
  virtual force_ifc vif;
  int calls = 0;
  function virtual force_ifc pick();
    ++calls;
    return vif;
  endfunction
  function logic [3:0] get();
    return vif.sig;
  endfunction
  function logic [2:0] get_low();
    return vif.sig[2:0];
  endfunction
  function logic [127:0] get_wide();
    return vif.wide;
  endfunction
  function logic [31:0] get_word(int index);
    return vif.words[index];
  endfunction
  function logic [15:0] get_halfword(int index);
    return vif.halfwords[index];
  endfunction
  function logic [14:0] get_narrow(int index);
    return vif.halfwords[index][14:0];
  endfunction
  function logic [62:0] get_qslice(int start);
    return vif.wide[start +: 63];
  endfunction
  function logic [64:0] get_wslice(int start);
    return vif.wide[start +: 65];
  endfunction
  function logic [511:0] get_words();
    return vif.words;
  endfunction
  function logic [2047:0] get_halfwords();
    return vif.halfwords;
  endfunction
  function logic [639:0] get_records();
    return vif.records;
  endfunction
  function logic [31:0] get_count(int row, int column);
    return vif.records[row][column].count;
  endfunction
  function logic [31:0] get_bytes(int row, int column);
    return vif.records[row][column].bytes;
  endfunction
  function logic [63:0] get_counter();
    return vif.counter;
  endfunction
  function logic [30:0] get_unforced_slice(int start);
    return vif.unforced_wide[start +: 31];
  endfunction
  function void set_halfword(int index, logic [15:0] value);
    vif.halfwords[index] = value;
  endfunction
  function real get_unforced_real();
    return vif.unforced_real;
  endfunction
endclass

module t;
  force_ifc i();
  force_ifc j();
  force_ifc k();
  logic [3:0] src = 4'h3;
  ForceReader r;

  initial begin
    r = new;
    r.vif = i;
    force i.sig = src;
    force j.sig = 4'h7;
    #1;
    `checkh(i.sig, 4'h3);
    `checkh(r.vif.sig, 4'h3);
    `checkh(r.get(), 4'h3);
    `checkh(r.get_low(), 3'h3);
    `checkh(r.pick().sig, 4'h3);
    `checkh(r.calls, 1);
    src = 4'ha;
    #1;
    `checkh(i.sig, 4'ha);
    `checkh(r.vif.sig, 4'ha);
    `checkh(r.get(), 4'ha);
    release i.sig;
    `checkh(r.get(), 4'ha);
    i.sig = 4'h5;
    `checkh(r.vif.sig, 4'h5);
    `checkh(r.get(), 4'h5);
    r.vif = j;
    `checkh(r.get(), 4'h7);
    release j.sig;
    `checkh(r.get(), 4'h7);
    k.sig = 4'h6;
    r.vif = k;
    `checkh(r.vif.sig, 4'h6);
    `checkh(r.get(), 4'h6);
  end

  logic [127:0] wide_source;
  logic [15:0][31:0] word_source;
  logic [127:0][15:0] halfword_source;
  force_packed_item_t [2:1][7:3] record_source;
  logic [63:0] counter_source;
  ForceReader packed_reader;
  initial begin
    packed_reader = new;
    packed_reader.vif = i;
    force i.wide = wide_source;
    force i.words = word_source;
    force i.halfwords = halfword_source;
    force i.records = record_source;
    force i.counter = counter_source;
    force j.halfwords = '1;
    force j.records = '1;
    // Non-integral reads remain raw; this control reads an unforced instance.
    force i.unforced_real = 2.0;
    k.unforced_real = 9.0;
    for (int cycle = 0; cycle < 3; ++cycle) begin
      wide_source = 128'hfedcba98765432100123456789abcdef ^ (128'(cycle + 1) << 65);
      counter_source = 64'h12345678abcdef09 ^ 64'(cycle);
      for (int index = 0; index < 16; ++index)
        word_source[index] = 32'h5a5a1234 + 32'(index + 17 * cycle);
      for (int index = 0; index < 128; ++index)
        halfword_source[index] = 16'(index + 131 * cycle);
      for (int row = 1; row <= 2; ++row) begin
        for (int column = 3; column <= 7; ++column) begin
          record_source[row][column].count = 32'(1000 + 17 * cycle + 5 * row + column);
          record_source[row][column].bytes = 32'(2000 + 19 * cycle + 7 * row + column);
        end
      end
      #1;
      `checkh(packed_reader.get_wide(), wide_source);
      `checkh(packed_reader.get_counter(), counter_source);
      `checkh(packed_reader.get_qslice(9 + cycle), wide_source[9 + cycle +: 63]);
      `checkh(packed_reader.get_wslice(33 + cycle), wide_source[33 + cycle +: 65]);
      `checkh(packed_reader.pick().wide[33 +: 65], wide_source[33 +: 65]);
      `checkh(packed_reader.calls, cycle + 1);
      `checkh(packed_reader.get_words(), word_source);
      `checkh(packed_reader.get_halfwords(), halfword_source);
      `checkh(packed_reader.get_records(), record_source);
      for (int index = 0; index < 16; ++index)
        `checkh(packed_reader.get_word(index), word_source[index]);
      for (int index = 0; index < 128; ++index) begin
        `checkh(packed_reader.get_halfword(index), halfword_source[index]);
        `checkh(packed_reader.get_narrow(index), halfword_source[index][14:0]);
      end
      for (int row = 1; row <= 2; ++row) begin
        for (int column = 3; column <= 7; ++column) begin
          `checkh(packed_reader.get_count(row, column), record_source[row][column].count);
          `checkh(packed_reader.get_bytes(row, column), record_source[row][column].bytes);
        end
      end
    end
    packed_reader.vif = j;
    `checkh(packed_reader.get_halfword(37), 16'hffff);
    `checkh(packed_reader.get_count(1, 3), 32'hffffffff);
    packed_reader.vif = k;
    packed_reader.set_halfword(37, 16'h8bad);
    k.unforced_wide = 96'hfedcba987654321001234567;
    `checkh(packed_reader.get_unforced_slice(17), k.unforced_wide[17 +: 31]);
    `checkh(packed_reader.get_halfword(37), 16'h8bad);
    if (packed_reader.get_unforced_real() != 9.0) `stop;
    packed_reader.vif = i;
    release i.halfwords;
    `checkh(packed_reader.get_halfwords(), halfword_source);
    i.halfwords = '0;
    `checkh(packed_reader.get_halfword(37), 0);
    release i.wide;
    release i.words;
    release i.records;
    release i.counter;
    release i.unforced_real;
    release j.halfwords;
    release j.records;
  end

  reg [1:0] a = 0;
  reg [1:0] b = 2;

  initial begin
    force b = a;
    `checkh(a, 0);
    `checkh(b, 0);
  end

  initial begin
    #1;
    `checkh(b, 0);

    a = 1;
    #1;
    `checkh(a, 1);
    `checkh(b, 1);

    a = 3;
    #1;
    `checkh(a, 3);
    `checkh(b, 3);

    release b;
    `checkh(a, 3);
    `checkh(b, 3);

    b = 0;
    #1;
    `checkh(b, 0);

    #1 $finish;
  end

endmodule
