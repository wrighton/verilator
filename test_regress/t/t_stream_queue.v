// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2025 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

`define stop $stop
`define checks(gotv,
               expv) do if ((gotv) != (expv)) begin $write("%%Error: %s:%0d:  got='%h' exp='%h'\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define checks_w(width, gotv, expv) do begin \
  logic [(width)-1:0] got_check; \
  logic [(width)-1:0] exp_check; \
  got_check = (gotv); \
  exp_check = (expv); \
  `checks(got_check, exp_check) \
end while(0);
module t;

  logic [7:0] i_char;
  logic [15:0] i_short;
  int i_header;
  int i_len;
  int i_data;
  int i_crc;

  logic [7:0] o_char;
  logic [15:0] o_short;
  int o_header;
  int o_len;
  int o_data;
  int o_crc;

  logic [128:0] wide129;
  int int_q[$];
  int int_r[$];
  shortint short_q[$];
  bit [6:0] s7_q[$];
  bit [12:0] d13_q[$];
  bit [12:0] s13_q[$];
  bit [6:0] d7_q[$];
  bit [7:0] s8_q[$];
  bit [23:0] d24_q[$];
  bit [23:0] s24_q[$];
  bit [31:0] d32_q[$];
  bit [31:0] s32_q[$];
  bit [32:0] s33_q[$];
  bit [65:0] d66_q[$];
  bit [64:0] s65_q[$];
  int int_d[];

  initial begin
    byte byte_pkt[$];
    logic [15:0] sdata_pkt[$];
    int int_pkt[$];
    logic [63:0] qdata_pkt[$];
    logic [128:0] vlwide_pkt_129[$];  //this is off by one to test edge cases
    logic [127:0] vlwide_pkt_128[$];
    /* verilator lint_off ASCRANGE */
    logic [0:7] byte_pkt_rev[$];
    logic [0:15] sdata_pkt_rev[$];
    logic [0:31] int_pkt_rev[$];
    logic [0:63] qdata_pkt_rev[$];
    logic [0:128] vlwide_pkt_129_rev[$];  //this is off by one to test edge cases
    logic [0:127] vlwide_pkt_128_rev[$];


    i_header = 12;
    i_len = 5;
    i_data = 11;
    i_crc = 42;
    i_char = 15;
    i_short = 16'hFF;
    #0;  // this forces no-life
    //TODO make this work with V3Life
    //-------------------- STREAML ------------------------------------
    //----------- CData QUEUE --------
    byte_pkt = {<<8{i_char}};
    o_char = {<<8{byte_pkt}};
    `checks(o_char, i_char);

    byte_pkt = {<<8{i_short}};
    o_short = {<<8{byte_pkt}};
    `checks(o_short, i_short);

    byte_pkt = {<<8{i_header}};
    o_header = {<<8{byte_pkt}};
    `checks(o_header, i_header);

    byte_pkt = {<<8{i_header, i_len}};
    {<<8{o_header, o_len}} = byte_pkt;
    `checks({i_header, i_len}, {o_header, o_len});

    byte_pkt = {<<8{i_header, i_len, i_crc, i_data}};
    {<<8{o_header, o_len, o_crc, o_data}} = byte_pkt;

    `checks_w(128, {>>{byte_pkt}}, {<<8{i_header, i_len, i_crc, i_data}});
    `checks_w(128, {i_header, i_len, i_crc, i_data}, {<<8{byte_pkt}});
    `checks({o_header, o_len, o_crc, o_data}, {i_header, i_len, i_crc, i_data});

    // //----------- SData QUEUE --------
    // sdata_pkt = {<<8{i_char}};
    //TODO This should compile
    // o_char = {{<<8{sdata_pkt}}}[7:0];
    // `checks(o_char,i_char);

    sdata_pkt = {<<8{i_short}};
    o_short = {<<8{sdata_pkt}};
    `checks(o_short, i_short);

    sdata_pkt = {<<8{i_header}};
    o_header = {<<8{sdata_pkt}};
    `checks(o_header, i_header);

    //test with QData
    sdata_pkt = {<<8{i_header, i_len}};
    {<<8{o_header, o_len}} = sdata_pkt;
    `checks({i_header, i_len}, {o_header, o_len});

    sdata_pkt = {<<8{i_header, i_len, i_crc, i_data}};
    {<<8{o_header, o_len, o_crc, o_data}} = sdata_pkt;

    `checks_w(128, {>>{sdata_pkt}}, {<<8{i_header, i_len, i_crc, i_data}});
    `checks({o_header, o_len, o_crc, o_data}, {i_header, i_len, i_crc, i_data});

    //----------- IData QUEUE --------
    int_pkt = {<<8{i_header}};
    o_header = {<<8{int_pkt}};
    `checks(o_header, i_header);

    //test with QData
    int_pkt = {<<8{i_header, i_len}};
    {<<8{o_header, o_len}} = int_pkt;
    `checks({i_header, i_len}, {o_header, o_len});

    int_pkt = {<<8{i_header, i_len, i_crc, i_data}};
    {<<8{o_header, o_len, o_crc, o_data}} = int_pkt;

    `checks_w(128, {>>{int_pkt}}, {<<8{i_header, i_len, i_crc, i_data}});
    `checks({o_header, o_len, o_crc, o_data}, {i_header, i_len, i_crc, i_data});

    //----------- QData QUEUE --------
    qdata_pkt = {<<8{i_header}};
    // o_header = {<<8{qdata_pkt}};
    //TODO This should compile
    // o_header = {{<<8{sdata_pkt}}}[32:0];
    // `checks(o_header,i_header);

    //test with QData
    qdata_pkt = {<<8{i_header, i_len}};
    {<<8{o_header, o_len}} = qdata_pkt;
    `checks({i_header, i_len}, {o_header, o_len});


    qdata_pkt = {<<8{i_header, i_len, i_crc, i_data}};
    {<<8{o_header, o_len, o_crc, o_data}} = qdata_pkt;

    `checks_w(128, {>>{qdata_pkt}}, {<<8{i_header, i_len, i_crc, i_data}});
    `checks({o_header, o_len, o_crc, o_data}, {i_header, i_len, i_crc, i_data});

    // ----------- VLWide QUEUE --------
    // test with QData
    vlwide_pkt_129 = {<<8{i_header, i_len}};
    {<<8{o_header,o_len}} = vlwide_pkt_129; //TODO this shouldn't compile lhs should not be smaller then rhs
    // `checks({i_header,i_len},{o_header,o_len});

    vlwide_pkt_129 = {<<8{i_header, i_len, i_crc, i_data}};

    /* verilator lint_off WIDTHEXPAND */
    wide129 = {<<8{i_header, i_len, i_crc, i_data}};
    `checks_w(129, {>>{vlwide_pkt_129}}, wide129);
    /* verilator lint_on WIDTHEXPAND */

    //------------------------------- REVERSE ENDIAN ------------------------------
    //----------- CData QUEUE --------
    byte_pkt_rev = {<<8{i_char}};
    o_char = {<<8{byte_pkt_rev}};
    `checks(o_char, i_char);

    byte_pkt_rev = {<<8{i_short}};
    o_short = {<<8{byte_pkt_rev}};
    `checks(o_short, i_short);

    byte_pkt_rev = {<<8{i_header}};
    o_header = {<<8{byte_pkt_rev}};
    `checks(o_header, i_header);

    byte_pkt_rev = {<<8{i_header, i_len}};
    {<<8{o_header, o_len}} = byte_pkt_rev;
    `checks({i_header, i_len}, {o_header, o_len});

    byte_pkt_rev = {<<8{i_header, i_len, i_crc, i_data}};
    {<<8{o_header, o_len, o_crc, o_data}} = byte_pkt_rev;

    `checks_w(128, {>>{byte_pkt_rev}}, {<<8{i_header, i_len, i_crc, i_data}});
    `checks_w(128, {i_header, i_len, i_crc, i_data}, {<<8{byte_pkt_rev}});
    `checks({o_header, o_len, o_crc, o_data}, {i_header, i_len, i_crc, i_data});

    //----------- SData QUEUE --------
    sdata_pkt_rev = {<<8{i_short}};
    o_short = {<<8{sdata_pkt_rev}};
    `checks(o_short, i_short);

    sdata_pkt_rev = {<<8{i_header}};
    o_header = {<<8{sdata_pkt_rev}};
    `checks(o_header, i_header);

    //test with QData
    sdata_pkt_rev = {<<8{i_header, i_len}};
    {<<8{o_header, o_len}} = sdata_pkt_rev;
    `checks({i_header, i_len}, {o_header, o_len});

    sdata_pkt_rev = {<<8{i_header, i_len, i_crc, i_data}};
    {<<8{o_header, o_len, o_crc, o_data}} = sdata_pkt_rev;

    `checks_w(128, {>>{sdata_pkt_rev}}, {<<8{i_header, i_len, i_crc, i_data}});
    `checks({o_header, o_len, o_crc, o_data}, {i_header, i_len, i_crc, i_data});

    //----------- IData QUEUE --------
    int_pkt_rev = {<<8{i_header}};
    o_header = {<<8{int_pkt_rev}};
    `checks(o_header, i_header);

    //test with QData
    int_pkt_rev = {<<8{i_header, i_len}};
    {<<8{o_header, o_len}} = int_pkt_rev;
    `checks({i_header, i_len}, {o_header, o_len});

    int_pkt_rev = {<<8{i_header, i_len, i_crc, i_data}};
    {<<8{o_header, o_len, o_crc, o_data}} = int_pkt_rev;

    `checks_w(128, {>>{int_pkt_rev}}, {<<8{i_header, i_len, i_crc, i_data}});
    `checks({o_header, o_len, o_crc, o_data}, {i_header, i_len, i_crc, i_data});

    //----------- QData QUEUE --------

    //test with QData
    qdata_pkt_rev = {<<8{i_header, i_len}};
    {<<8{o_header, o_len}} = qdata_pkt_rev;
    `checks({i_header, i_len}, {o_header, o_len});


    qdata_pkt_rev = {<<8{i_header, i_len, i_crc, i_data}};
    {<<8{o_header, o_len, o_crc, o_data}} = qdata_pkt_rev;

    `checks_w(128, {>>{qdata_pkt_rev}}, {<<8{i_header, i_len, i_crc, i_data}});
    `checks({o_header, o_len, o_crc, o_data}, {i_header, i_len, i_crc, i_data});

    // ----------- VLWide QUEUE --------

    vlwide_pkt_129_rev = {<<8{i_header, i_len, i_crc, i_data}};
    /* verilator lint_off WIDTHEXPAND */
    wide129 = {<<8{i_header, i_len, i_crc, i_data}};
    /* verilator lint_on WIDTHEXPAND */
    `checks_w(129, {>>{vlwide_pkt_129_rev}}, wide129);

    // // -------------------- STREAMR ------------------------------------
    // //----------- CData QUEUE --------
    byte_pkt = {>>{i_header}};
    o_header = {>>{byte_pkt}};
    `checks(o_header, i_header);

    byte_pkt = {>>{i_header, i_len}};
    {>>{o_header, o_len}} = byte_pkt;
    `checks_w(64, {>>{i_header, i_len}}, {>>{o_header, o_len}});
    `checks({i_header, i_len}, {o_header, o_len});

    byte_pkt = {>>{i_header, i_len, i_crc, i_data}};
    {>>{o_header, o_len, o_crc, o_data}} = byte_pkt;

    `checks_w(128, {>>{byte_pkt}}, {>>{i_header, i_len, i_crc, i_data}});
    `checks({o_header, o_len, o_crc, o_data}, {i_header, i_len, i_crc, i_data});

    //----------- IData QUEUE --------
    int_pkt = {>>{i_header}};
    o_header = {>>{int_pkt}};
    `checks(o_header, i_header);
    `checks_w(32, o_header, {>>{int_pkt}});
    `checks_w(32, {>>{o_header}}, {>>{int_pkt}});

    //test with QData
    int_pkt = {>>{i_header, i_len}};
    {>>{o_header, o_len}} = int_pkt;
    `checks({i_header, i_len}, {o_header, o_len});

    int_pkt = {>>{i_header, i_len, i_crc, i_data}};
    {>>{o_header, o_len, o_crc, o_data}} = int_pkt;

    `checks_w(128, {>>{int_pkt}}, {>>{i_header, i_len, i_crc, i_data}});
    `checks({o_header, o_len, o_crc, o_data}, {i_header, i_len, i_crc, i_data});

    //----------- QData QUEUE --------

    // test with QData
    qdata_pkt = {>>{i_header, i_len}};
    {>>{o_header, o_len}} = qdata_pkt;
    `checks({i_header, i_len}, {o_header, o_len});

    qdata_pkt = {>>{i_header, i_len, i_crc, i_data}};
    {>>{o_header, o_len, o_crc, o_data}} = qdata_pkt;

    `checks_w(128, {>>{qdata_pkt}}, {>>{i_header, i_len, i_crc, i_data}});
    `checks({o_header, o_len, o_crc, o_data}, {i_header, i_len, i_crc, i_data});

    // ----------- VLWide QUEUE --------

    // test with QData
    vlwide_pkt_129 = {>>{i_header, i_len}};
    {>>{o_header, o_len}} = vlwide_pkt_129;
    `checks({i_header, i_len}, {o_header, o_len});


    vlwide_pkt_129 = {>>{i_header, i_len, i_crc, i_data}};
    {>>{o_header, o_len, o_crc, o_data}} = vlwide_pkt_129;

    `checks_w(129, {>>{vlwide_pkt_129}}, {>>{i_header, i_len, i_crc, i_data, 1'b0}});
    `checks({o_header, o_len, o_crc, o_data}, {i_header, i_len, i_crc, i_data});

    //---------- into other queues ------
    int_pkt = {>>{i_header, i_len, i_crc, i_data}};
    byte_pkt = {>>{int_pkt}};
    `checks_w(128, {>>{byte_pkt}}, {>>{i_header, i_len, i_crc, i_data}});

    byte_pkt = {>>{i_header, i_len, i_crc, i_data}};
    int_pkt = {>>{byte_pkt}};
    `checks_w(128, {>>{int_pkt}}, {>>{i_header, i_len, i_crc, i_data}});

    byte_pkt = {>>{i_header, i_len, i_crc, i_data}};
    int_pkt = {>>{byte_pkt}};
    `checks_w(128, {>>{int_pkt}}, {>>{i_header, i_len, i_crc, i_data}});

    sdata_pkt = {>>{i_header, i_len, i_crc, i_data}};
    byte_pkt = {>>{sdata_pkt}};
    `checks_w(128, {>>{byte_pkt}}, {>>{i_header, i_len, i_crc, i_data}});

    byte_pkt = {>>{i_header, i_len, i_crc, i_data}};
    sdata_pkt = {>>{byte_pkt}};
    `checks_w(128, {>>{sdata_pkt}}, {>>{i_header, i_len, i_crc, i_data}});

    byte_pkt = {>>{i_header, i_len, i_crc, i_data}};
    qdata_pkt = {>>{byte_pkt}};
    `checks_w(128, {>>{qdata_pkt}}, {>>{i_header, i_len, i_crc, i_data}});

    qdata_pkt = {>>{i_header, i_len, i_crc, i_data}};
    byte_pkt = {>>{qdata_pkt}};
    `checks_w(128, {>>{byte_pkt}}, {>>{i_header, i_len, i_crc, i_data}});

    qdata_pkt = {>>{i_header, i_len, i_crc, i_data}};
    int_pkt = {>>{qdata_pkt}};
    `checks_w(128, {>>{int_pkt}}, {>>{i_header, i_len, i_crc, i_data}});

    int_pkt = {>>{i_header, i_len, i_crc, i_data}};
    qdata_pkt = {>>{int_pkt}};
    `checks_w(128, {>>{qdata_pkt}}, {>>{i_header, i_len, i_crc, i_data}});

    byte_pkt = {>>{i_header, i_len, i_crc, i_data}};
    vlwide_pkt_128 = {>>{byte_pkt}};
    `checks_w(128, {>>{vlwide_pkt_128}}, {>>{i_header, i_len, i_crc, i_data}});

    vlwide_pkt_128 = {>>{i_header, i_len, i_crc, i_data}};
    byte_pkt = {>>{vlwide_pkt_128}};
    `checks_w(128, {i_header, i_len, i_crc, i_data}, {>>{byte_pkt}});
    `checks_w(128, {>>{byte_pkt}}, {>>{i_header, i_len, i_crc, i_data}});

    int_pkt = {>>{i_header, i_len, i_crc, i_data}};
    vlwide_pkt_128 = {>>{int_pkt}};
    `checks_w(128, {i_header, i_len, i_crc, i_data}, {>>{vlwide_pkt_128}});
    `checks_w(128, {>>{vlwide_pkt_128}}, {>>{i_header, i_len, i_crc, i_data}});

    vlwide_pkt_128 = {>>{i_header, i_len, i_crc, i_data}};
    int_pkt = {>>{vlwide_pkt_128}};
    `checks_w(128, {i_header, i_len, i_crc, i_data}, {>>{int_pkt}});
    `checks_w(128, {>>{int_pkt}}, {>>{i_header, i_len, i_crc, i_data}});

    qdata_pkt = {>>{i_header, i_len, i_crc, i_data}};
    vlwide_pkt_128 = {>>{qdata_pkt}};
    `checks_w(128, {i_header, i_len, i_crc, i_data}, {>>{vlwide_pkt_128}});
    `checks_w(128, {>>{vlwide_pkt_128}}, {>>{i_header, i_len, i_crc, i_data}});

    qdata_pkt = {>>{i_header, i_len, i_crc, i_data, i_header, i_len, i_crc, i_data}};
    vlwide_pkt_128 = {>>{qdata_pkt}};
    `checks_w(256, {i_header, i_len, i_crc, i_data, i_header, i_len, i_crc, i_data},
              {>>{vlwide_pkt_128}});
    `checks_w(256, {>>{vlwide_pkt_128}},
              {>>{i_header, i_len, i_crc, i_data, i_header, i_len, i_crc, i_data}});

    qdata_pkt = {>>{i_header, i_len, i_crc, i_data, i_header, i_len, i_crc}};
    vlwide_pkt_128 = {>>{qdata_pkt}};
    `checks_w(256, {i_header, i_len, i_crc, i_data, i_header, i_len, i_crc, 32'h0},
              {>>{vlwide_pkt_128}});
    `checks_w(256, {>>{vlwide_pkt_128}},
              {>>{i_header, i_len, i_crc, i_data, i_header, i_len, i_crc, 32'h0}});

    vlwide_pkt_128 = {>>{i_header, i_len, i_crc, i_data}};
    qdata_pkt = {>>{vlwide_pkt_128}};
    `checks_w(128, {i_header, i_len, i_crc, i_data}, {>>{vlwide_pkt_128}});
    `checks_w(128, {>>{qdata_pkt}}, {>>{i_header, i_len, i_crc, i_data}});

    // Queues of elements of the same width, or of two narrower ones in each element
    int_q = '{32'h1, 32'h2, 32'h3, 32'h4};
    int_r = {>>{int_q}};
    `checks(int_r.size(), 4);
    `checks_w(128, {>>{int_r}}, 128'h00000001_00000002_00000003_00000004);
    int_q = '{32'h7, 32'h8, 32'h9};
    int_r = {>>{int_q}};
    `checks(int_r.size(), 3);
    `checks_w(96, {>>{int_r}}, 96'h00000007_00000008_00000009);
    short_q = '{16'h1111, 16'h2222, 16'h3333, 16'h4444, 16'h5555, 16'h6666};
    int_r = {>>{short_q}};
    `checks(int_r.size(), 3);
    `checks_w(96, {>>{int_r}}, 96'h11112222_33334444_55556666);
    // Element widths that are not those of their C++ types. The streams are whole numbers of the
    // target elements; the result of others is not defined (IEEE 1800-2023 6.24.3).
    s7_q = '{7'h6e, 7'h53, 7'h7b, 7'h7d, 7'h15, 7'h7e, 7'h1a, 7'h48, 7'h29, 7'h2b, 7'h50, 7'h13,
             7'h24};
    d13_q = {>>{s7_q}};
    `checks(d13_q.size(), 7);
    `checks_w(91, {>>{d13_q}}, 91'h6ea7efe95fc6a42957409a4);
    s13_q = '{13'h17a7, 13'h893, 13'h6a0, 13'h135, 13'h415, 13'hd8e, 13'h1c23};
    d7_q = {>>{s13_q}};
    `checks(d7_q.size(), 13);
    `checks_w(91, {>>{d7_q}}, 91'h5e9d1266a009a9055b1dc23);
    s8_q = '{8'h19, 8'hd4, 8'h0};
    d24_q = {>>{s8_q}};
    `checks(d24_q.size(), 1);
    `checks_w(24, {>>{d24_q}}, 24'h19d400);
    s24_q = '{24'h780a5f, 24'hc9f9f6, 24'h3c2977, 24'h9ac32c};
    d32_q = {>>{s24_q}};
    `checks(d32_q.size(), 3);
    `checks_w(96, {>>{d32_q}}, 96'h780a5fc9f9f63c29779ac32c);
    s32_q = '{32'h43b9c5db, 32'h4b47799c, 32'h29002ce9};
    d24_q = {>>{s32_q}};
    `checks(d24_q.size(), 4);
    `checks_w(96, {>>{d24_q}}, 96'h43b9c5db4b47799c29002ce9);
    s33_q = '{33'h25696179, 33'h16dff7d29};
    d66_q = {>>{s33_q}};
    `checks(d66_q.size(), 1);
    `checks_w(66, {>>{d66_q}}, 66'h4ad2c2f36dff7d29);
    s65_q = '{65'h18c70b77e9359ec32, 65'h3569d15b4f3f629};
    d13_q = {>>{s65_q}};
    `checks(d13_q.size(), 10);
    `checks_w(130, {>>{d13_q}}, 130'h318e16efd26b3d86403569d15b4f3f629);
    // A dynamic array source
    int_d = '{32'h7, 32'h8, 32'h9};
    int_r = {>>{int_d}};
    `checks(int_r.size(), 3);
    `checks_w(96, {>>{int_r}}, 96'h00000007_00000008_00000009);
    $write("*-* All Finished *-*\n");
    $finish;

  end


endmodule
