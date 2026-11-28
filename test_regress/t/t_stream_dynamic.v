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

  // Dynamically sized operand into fixed-size unpacked arrays
  task test4;
    int q[$];
    byte dyn8[];
    int up3[3];
    int up4[4];
    int desc[4:2];
    int asc[1:3];
    bit [14:0] up15[2];
    bit [94:0] up95[2];
    byte q8[$];
    bit [7:0] a1[1];
    byte bq8[$:4];
    bit [7:0] a3[3];

    q.push_back(1);
    q.push_back(2);
    q.push_back(3);
    up3 = {>>{q}};
    `checkp(up3, "'{'h1, 'h2, 'h3}");
    // A narrower stream is zero-filled on the right
    up4 = '{9, 9, 9, 9};
    up4 = {>>{q}};
    `checkp(up4, "'{'h1, 'h2, 'h3, 'h0}");
    up3 = {<<8{q}};
    `checkp(up3, "'{'h3000000, 'h2000000, 'h1000000}");
    desc = {>>{q}};
    `checkh(desc[4], 1);
    `checkh(desc[3], 2);
    `checkh(desc[2], 3);
    asc = {<<{q}};
    `checkh(asc[1], 32'hc0000000);
    `checkh(asc[2], 32'h40000000);
    `checkh(asc[3], 32'h80000000);
    up95 = '{'1, '1};
    up95 = {>>{q}};
    `checkh(up95[0], 95'h0_80000001_00000001);
    `checkh(up95[1], 95'h40000000_00000000_00000000);

    dyn8 = new[3] ('{8'h12, 8'h34, 8'h56});
    up15 = {>>{dyn8}};
    `checkh(up15[0], 15'h091a);
    `checkh(up15[1], 15'h1580);

    // Bytes into a byte array, not filling a 32-bit word
    q8 = '{8'h41};
    a1 = {>>{q8}};
    `checkh(a1[0], 8'h41);
    q8 = '{8'h61, 8'h5a, 8'h21};
    a3 = {>>{q8}};
    `checkp(a3, "'{'h61, 'h5a, 'h21}");
    a3 = {<<8{q8}};
    `checkp(a3, "'{'h21, 'h5a, 'h61}");
    // From a bounded queue
    bq8 = '{8'h41};
    a1 = {>>{bq8}};
    `checkh(a1[0], 8'h41);
    bq8 = '{8'h61, 8'h5a, 8'h21};
    a3 = {<<8{bq8}};
    `checkp(a3, "'{'h21, 'h5a, 'h61}");
  endtask

  // Dynamically sized operand into a concatenation of variables
  task test5;
    byte q8[$];
    bit [7:0] a;
    bit [15:0] b;
    bit [3:0] c;
    bit [3:0] d;

    q8 = '{8'h12, 8'h34, 8'h56};
    {a, b} = {>>{q8}};
    `checkh(a, 8'h12);
    `checkh(b, 16'h3456);
    {a, b} = {<<8{q8}};
    `checkh(a, 8'h56);
    `checkh(b, 16'h3412);
    {a, b} = {<<{q8}};
    `checkh(a, 8'h6a);
    `checkh(b, 16'h2c48);
    // A shorter stream is zero-filled on the right
    q8 = '{8'h9a};
    {a, b} = {>>{q8}};
    `checkh(a, 8'h9a);
    `checkh(b, 16'h0);
    {c, d} = {>>{q8}};
    `checkh(c, 4'h9);
    `checkh(d, 4'ha);
  endtask

  initial begin
    test1();
    test2();
    test3();
    test4();
    test5();
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
