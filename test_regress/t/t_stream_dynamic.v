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

  typedef logic [7:0] byte_t;
  task test4;
    byte_t tq[$];
    int dyn32[];
    byte dyn8[];
    byte q8[$];
    logic [99:0] q100[$];
    logic [31:0] a;
    logic [31:0] b;
    byte c;
    byte d;
    logic [11:0] w12;
    logic [99:0] w100;

    // Unpacking a dynamic array or queue into a concatenation
    dyn32 = '{32'h11223344, 32'h55667788};
    {>>{a, b}} = dyn32;
    `checkh(a, 32'h11223344);
    `checkh(b, 32'h55667788);
    dyn8 = '{8'h11, 8'h22};
    {>>{c, d}} = dyn8;
    `checkh(c, 8'h11);
    `checkh(d, 8'h22);
    q8 = '{8'h11, 8'h22, 8'h33, 8'h44, 8'h55, 8'h66, 8'h77, 8'h88};
    {>>{a, b}} = q8;
    `checkh(a, 32'h11223344);
    `checkh(b, 32'h55667788);
    tq = '{8'h5a, 8'ha5};
    {>>{c, d}} = tq;
    `checkh(c, 8'h5a);
    `checkh(d, 8'ha5);

    // Bits beyond the target are ignored
    q8 = '{8'h33, 8'h44, 8'h55};
    {>>{c, d}} = q8;
    `checkh(c, 8'h33);
    `checkh(d, 8'h44);
    {>>{w12}} = q8;
    `checkh(w12, 12'h334);
    q8 = '{8'h11, 8'h22, 8'h33, 8'h44, 8'h55, 8'h66, 8'h77, 8'h88, 8'h99, 8'haa, 8'hbb, 8'hcc,
           8'hdd, 8'hee};
    {>>{w100}} = q8;
    `checkh(w100, 100'h112233445566778899aabbccd);
    q100 = '{100'h123456789abcdef0123456789, 100'hfedcba9876543210fedcba987};
    {>>{a}} = q100;
    `checkh(a, 32'h12345678);
    {>>{a, w100}} = q100;
    `checkh(a, 32'h12345678);
    `checkh(w100, 100'h9abcdef0123456789fedcba98);
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
