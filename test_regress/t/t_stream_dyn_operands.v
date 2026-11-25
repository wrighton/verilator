// DESCRIPTION: Verilator: Verilog Test module
//
// A streaming concatenation with a dynamic array or queue among its operands
// (IEEE 1800-2023 11.4.14): packing streams the bits of all operands, and
// unpacking gives the first dynamically sized operand all bits but those of
// the fixed-size operands after it, and later ones none.
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define checkp(gotv,expv_s) do begin string gotv_s; gotv_s = $sformatf("%p", gotv); if ((gotv_s) != (expv_s)) begin $write("%%Error: %s:%0d:  got='%s' exp='%s'\n", `__FILE__,`__LINE__, (gotv_s), (expv_s)); `stop; end end while(0);
// verilog_format: on

module t;
  byte unsigned hdr;
  byte unsigned dyn[];
  wire [31:0] cont = {>>{hdr, dyn}};

  function automatic bit [31:0] pack_args(byte unsigned first, byte unsigned rest[]);
    return {>>{first, rest}};
  endfunction

  // Packing
  initial begin
    byte unsigned arr[2];
    bit [3:0] q4[$];
    bit [6:0] w7;
    bit [39:0] p40;
    byte unsigned q8[$];
    for (int i = 0; i < 2; ++i) begin
      hdr = 8'h11 + 8'(i);
      dyn = '{8'h33, 8'h44, 8'h55};
      arr = '{8'haa, 8'hbb};
      p40 = {>>{hdr, 8'h22, dyn}};
      `checkh(p40, {hdr, 32'h22334455});
      p40 = {<<8{hdr, 8'h22, dyn}};
      `checkh(p40, {32'h55443322, hdr});
      p40 = {>>{hdr, dyn}};  // Left-justified
      `checkh(p40, {hdr, 32'h33445500});
      p40 = {>>{arr, dyn}};
      `checkh(p40, {16'haabb, 24'h334455});
      q8 = {>>{dyn, hdr, dyn}};
      `checkp(q8, i == 0 ? "'{'h33, 'h44, 'h55, 'h11, 'h33, 'h44, 'h55}"
                         : "'{'h33, 'h44, 'h55, 'h12, 'h33, 'h44, 'h55}");
      q8 = {<<4{hdr, dyn}};
      `checkp(q8, i == 0 ? "'{'h55, 'h44, 'h33, 'h11}" : "'{'h55, 'h44, 'h33, 'h21}");
      w7 = 7'h5a + 7'(i);
      q4 = '{4'h1, 4'h2};
      p40 = {>>{hdr, {<<8{dyn}}, 8'h66}};  // A stream of a dynamically sized operand
      `checkh(p40, {hdr, 32'h55443366});
      p40 = {>>{hdr, {<<{dyn}}}};
      `checkh(p40, {hdr, 32'haa22cc00});
      p40 = {>>{w7, q4, 1'b1}};  // Not whole bytes
      `checkh(p40, {w7, 8'h12, 1'b1, 24'h0});
      `checkh(pack_args(hdr, dyn), {hdr, 24'h334455});
      #1 `checkh(cont, {hdr, 24'h334455});
    end
  end

  // Unpacking
  initial begin
    byte unsigned a, b;
    byte unsigned d1[];
    byte unsigned d2[$];
    bit [11:0] w12;
    bit [3:0] n4[$];
    byte unsigned src[$];
    #10;
    for (int i = 0; i < 2; ++i) begin
      {>>{a, d1}} = {8'hab, 8'(i)};
      `checkh(a, 8'hab);
      `checkp(d1, i == 0 ? "'{'h0}" : "'{'h1}");
      d2 = '{8'h99};
      {>>{a, d1, d2, b}} = {32'h01020304, 8'(i)};  // The second dynamic operand takes none
      `checkh(a, 8'h01);
      `checkp(d1, "'{'h2, 'h3, 'h4}");
      `checkp(d2, "'{}");
      `checkh(b, 8'(i));
      {>>{a, d1, b}} = {8'h0c, 8'(i)};  // Exactly the bits of the fixed-size operands
      `checkh(a, 8'h0c);
      `checkp(d1, "'{}");
      `checkh(b, 8'(i));
      {>>{a, {<<8{d1}}}} = {24'h0d0e0f, 8'(i)};  // A stream of a dynamically sized operand
      `checkh(a, 8'h0d);
      `checkp(d1, i == 0 ? "'{'h0, 'hf, 'he}" : "'{'h1, 'hf, 'he}");
      d2 = '{8'h99};
      {>>{d1, {<<8{d2}}}} = 16'h1234;
      `checkp(d1, "'{'h12, 'h34}");
      `checkp(d2, "'{}");
      {<<8{a, d1}} = {16'h0a0b, 8'(i)};
      `checkh(a, 8'(i));
      `checkp(d1, "'{'hb, 'ha}");
      src = '{8'hde, 8'had, 8'hbe, 8'(i)};
      {>>{w12, n4}} = src;
      `checkh(w12, 12'hdea);
      `checkp(n4, i == 0 ? "'{'hd, 'hb, 'he, 'h0, 'h0}" : "'{'hd, 'hb, 'he, 'h0, 'h1}");
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
