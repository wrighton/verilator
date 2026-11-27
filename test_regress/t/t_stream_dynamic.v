// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2023 Antmicro Ltd
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define checkp(gotv,expv_s) do begin string gotv_s; gotv_s = $sformatf("%p", gotv); if ((gotv_s) != (expv_s)) begin $write("%%Error: %s:%0d:  got='%s' exp='%s'\n", `__FILE__,`__LINE__, (gotv_s), (expv_s)); `stop; end end while(0);
// verilog_format: on

typedef enum bit [5:0] {
  A = 6'b111000,
  B = 6,
  b111111
} enum_t;

module t;
  int big = 32'sh7fff_ffff;
  longint wide = 64'sh1_0000_0000;
  task test1;
    bit arr[];
    bit [1:0] arr2[$];
    bit [5:0] arr6[$];
    bit [5:0] bit6;
    bit [5:0] ans;
    bit [3:0] arr4[];
    bit [7:0] arr8[];
    bit [63:0] arr64[];
    bit [159:0] arr160[];
    bit [63:0] bit64;
    bit [99:0] bit100;
    bit [319:0] bit320;
    enum_t ans_enum;

    bit6 = 6'b111000;
    arr4 = '{25{4'b1000}};
    arr8 = '{8{8'b00110011}};
    arr64 = '{5{64'h0123456789abcdef}};
    arr160 = '{2{160'h0123456789abcdef0123456789abcdef01234567}};

    {>>bit{arr}} = bit6;
    `checkp(arr, "'{'h1, 'h1, 'h1, 'h0, 'h0, 'h0}");
    ans = {>>bit{arr}};
    `checkh(ans, bit6);

    ans_enum = enum_t'({>>bit{arr}});
    `checkh(ans_enum, bit6);

    {<<bit{arr}} = bit6;
    `checkp(arr, "'{'h0, 'h0, 'h0, 'h1, 'h1, 'h1}");

    ans = {<<bit{arr}};
    `checkh(ans, bit6);

    ans_enum = enum_t'({<<bit{arr}});
    `checkh(ans_enum, bit6);

`ifdef VERILATOR
    // This set flags errors on other simulators
    {>>bit[1:0] {arr2}} = bit6;
    `checkp(arr2, "'{'h3, 'h2, 'h0}");

    ans = {>>bit[1:0] {arr2}};
    `checkh(ans, bit6);

    ans_enum = enum_t'({>>bit[1:0] {arr2}});
    `checkh(ans_enum, bit6);

    {<<bit[1:0] {arr2}} = bit6;
    `checkp(arr2, "'{'h0, 'h2, 'h3}");

    ans = {<<bit[1:0] {arr2}};
    `checkh(ans, bit6);

    ans_enum = enum_t'({<<bit[1:0] {arr2}});
    `checkh(ans_enum, bit6);

    {>>bit[5:0] {arr6}} = bit6;
    `checkp(arr6, "'{'h38}");

    ans = {>>bit[5:0] {arr6}};
    `checkh(ans, bit6);

    ans_enum = enum_t'({>>bit[5:0] {arr6}});
    `checkh(ans_enum, bit6);

    {<<bit[5:0] {arr6}} = bit6;
    `checkp(arr6, "'{'h38}");

    ans = {<<bit[5:0] {arr6}};
    `checkh(ans, bit6);

    ans_enum = enum_t'({<<bit[5:0] {arr6}});
    `checkh(ans_enum, bit6);
`endif

    bit64 = {>>bit{arr8}};
    `checkh(bit64[7:0], 8'b00110011);
    bit64 = {<<bit{arr8}};
    `checkh(bit64[7:0], 8'b11001100);

    {>>bit{arr8}} = bit64;
    `checkh(arr8[0], 8'b11001100);
    {<<bit{arr8}} = bit64;
    `checkh(arr8[0], 8'b00110011);

    bit100 = {>>bit{arr4}};
    `checkh(bit100[3:0], 4'b1000);
    bit100 = {<<bit{arr4}};
    `checkh(bit100[3:0], 4'b0001);

    {>>bit{arr4}} = bit100;
    `checkh(arr4[0], 4'b0001);
    {<<bit{arr4}} = bit100;
    `checkh(arr4[0], 4'b1000);

    bit320 = {>>byte{arr64}};
    `checkh(bit320[63:0], 64'h0123456789abcdef);
    bit320 = {<<byte{arr64}};
    `checkh(bit320[63:0], 64'hefcdab8967452301);

    {>>byte{arr64}} = bit320;
    `checkh(arr64[0], 64'hefcdab8967452301);
    {<<byte{arr64}} = bit320;
    `checkh(arr64[0], 64'h0123456789abcdef);

    {>>bit{arr64}} = bit64;
    `checkh(arr64[0], 64'hcccccccccccccccc);
    {<<bit{arr64}} = bit64;
    `checkh(arr64[0], 64'h3333333333333333);

    bit64 = {>>bit{arr64}};
    `checkh(bit64, 64'h3333333333333333);
    bit64 = {<<bit{arr64}};
    `checkh(bit64, 64'hcccccccccccccccc);

    bit320 = {>>byte{arr160}};
    `checkh(bit320[159:0], 160'h0123456789abcdef0123456789abcdef01234567);
    bit320 = {<<byte{arr160}};
    `checkh(bit320[159:0], 160'h67452301efcdab8967452301efcdab8967452301);

    {>>byte{arr160}} = bit320;
    `checkh(arr160[0], 160'h67452301efcdab8967452301efcdab8967452301);
    {<<byte{arr160}} = bit320;
    `checkh(arr160[0], 160'h0123456789abcdef0123456789abcdef01234567);
  endtask

  task test2;
    byte unpack[8];  // [0] is left-most for purposes of streaming
    bit [63:0] bits;  // [63] is left-most for purposes of streaming
    longint word;  // [63] is left-most for purposes of streaming

    // Using packed bits
    $display("Test2");
    bits = {8'hfa, 8'hde, 8'hca, 8'hfe, 8'hde, 8'had, 8'hbe, 8'hef};
    word = {>>{bits}};
    `checkh(word, 64'hfadecafedeadbeef);
    word = {<<8{bits}};
    `checkh(word, 64'hefbeaddefecadefa);

    // Using byte unpacked array
    unpack = '{8'hfa, 8'hde, 8'hca, 8'hfe, 8'hde, 8'had, 8'hbe, 8'hef};
    `checkh(unpack[0], 8'hfa);
    `checkh(unpack[7], 8'hef);
    word = {>>{unpack}};
    `checkh(word, 64'hfadecafedeadbeef);
    word = {<<8{unpack}};
    `checkh(word, 64'hefbeaddefecadefa);
  endtask

  task test3;
    byte dyn8[];  // [0] is left-most for purposes of streaming
    longint word;  // [63] is left-most for purposes of streaming
    // verilator lint_off ASCRANGE
    bit [0:63] rbits;  // [63] is still left-most for purposes of streaming
    // verilator lint_on ASCRANGE

    // Using byte dynamic array
    dyn8 = new[8] ('{8'hfa, 8'hde, 8'hca, 8'hfe, 8'hde, 8'had, 8'hbe, 8'hef});
    `checkh(dyn8[0], 8'hfa);
    `checkh(dyn8[7], 8'hef);
    word = {>>{dyn8}};
    `checkh(word, 64'hfadecafedeadbeef);
    word = {<<1{dyn8}};
    `checkh(word, 64'hf77db57b7f537b5f);
    word = {<<8{dyn8}};
    `checkh(word, 64'hefbeaddefecadefa);

    rbits = {>>{dyn8}};
    `checkh(rbits, 64'hfadecafedeadbeef);
    rbits = {<<1{dyn8}};
    `checkh(rbits, 64'hf77db57b7f537b5f);
    rbits = {<<8{dyn8}};
    `checkh(rbits, 64'hefbeaddefecadefa);
  endtask

  task test4;
    // Items of unpacked arrays selected by with[]
    byte unsigned data[];
    byte unsigned q[$];
    byte unsigned f[4];
    byte unsigned fd[3:0];
    int unsigned n;
    bit [15:0] p16;
    bit [7:0] p8;
    data = '{8'h11, 8'h22, 8'h33, 8'h44};
    q = '{8'h55, 8'h66, 8'h77};
    f = '{8'h01, 8'h02, 8'h03, 8'h04};
    n = 2;
    data = {>>{data with [0:n-1]}};
    `checkh(data.size(), 2);
    `checkh(data[0], 8'h11);
    `checkh(data[1], 8'h22);
    p16 = {>>{q with [n-1+:2]}};
    `checkh(p16, 16'h6677);
    p16 = {<<8{q with [n-:2]}};
    `checkh(p16, 16'h7766);
    p8 = {>>{f with [n]}};
    `checkh(p8, 8'h03);
    p16 = {>>{f with [1:2]}};
    `checkh(p16, 16'h0203);
    // As the matching slice of a descending array
    fd = '{8'h04, 8'h03, 8'h02, 8'h01};
    p16 = {>>{fd with [2:1]}};
    `checkh(p16, 16'h0302);
    // A range past the end of the array streams it, then the default value for the items it lacks
    q = '{8'h11, 8'h22};
    data = {>>{q with [0:3]}};
    `checkp(data, "'{'h11, 'h22, 'h0, 'h0}");
    data = {>>{q with [$-3:$]}};
    `checkp(data, "'{'h0, 'h0, 'h11, 'h22}");
    data = {>>{q with [-1:$]}};
    `checkp(data, "'{'h0, 'h11, 'h22}");
    data = {>>{q with [0:$-(-2)]}};
    `checkp(data, "'{'h11, 'h22, 'h0, 'h0}");
    data = {>>{q with [big+:2]}};
    `checkp(data, "'{'h0, 'h0}");
    data = {>>{q with [big-1+:2]}};
    `checkp(data, "'{'h0, 'h0}");
    data = {>>{q with [wide+:2]}};
    `checkp(data, "'{'h0, 'h0}");
    data = {>>{q with [64'sh1_0000_0000:64'sh1_0000_0001]}};
    `checkp(data, "'{'h0, 'h0}");
    // A range with an unknown position selects no element
    data = {>>{q with [4'bx000:$]}};
    `checkp(data, "'{}");
    // verilator lint_off WIDTHEXPAND
    data = {>>{q with [$:$-4'bx001]}};
    // verilator lint_on WIDTHEXPAND
    `checkp(data, "'{}");
    // Too large to read padded, so the whole array
    data = {>>{q with [0:64'sh1_0000_0000]}};
    `checkp(data, "'{'h11, 'h22}");
    data = {>>{q with [0:wide]}};
    `checkp(data, "'{'h11, 'h22}");
    // A range of variable size is limited to the array
    data = {>>{q with [0:n+999999999]}};
    `checkp(data, "'{'h11, 'h22}");
    data = {>>{q with [n-1+:3]}};
    `checkp(data, "'{'h22, 'h0, 'h0}");
    data = '{8'h11, 8'h22, 8'h33};
    data = {>>{data with [1:5]}};
    `checkp(data, "'{'h22, 'h33, 'h0, 'h0, 'h0}");
    begin
      // Not limited by the bound of the queue
      byte unsigned bq[$:3];
      bq = '{8'h11, 8'h22};
      data = {>>{bq with [0:5]}};
      `checkp(data, "'{'h11, 'h22, 'h0, 'h0, 'h0, 'h0}");
    end
  endtask

  initial begin
    test1();
    test2();
    test3();
    test4();
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
