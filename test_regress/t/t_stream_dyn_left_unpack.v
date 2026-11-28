// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define checkp(gotv,expv_s) do begin string gotv_s; gotv_s = $sformatf("%p", gotv); if ((gotv_s) != (expv_s)) begin $write("%%Error: %s:%0d:  got='%s' exp='%s'\n", `__FILE__,`__LINE__, (gotv_s), (expv_s)); `stop; end end while(0);
// verilog_format: on

// A left stream target of a dynamically sized array, unpacked as the inverse of the stream's
// packing: its source is sliced from the left, the short slice the rightmost
// (IEEE 1800-2023 11.4.14.2, 11.4.14.3)
module t;
  bit [6:0] q7[$];
  bit [3:0] d4[$];
  bit [3:0] dd4[];
  bit [3:0] d4b[$:6];
  bit [6:0] q7b[$];
  byte q8[$];
  byte d8[$];

  initial begin
    // 28 bits into 4-bit elements, sliced by 5: 5 + 5 + 5 + 5 + 5 + 3
    q7 = '{7'h4d, 7'h77, 7'h21, 7'h6c};
    {<<5{d4}} = q7;
    `checkp(d4, "'{'h9, 'hd, 'h8, 'h3, 'h9, 'hf, 'h3}");
    // A pack followed by the unpack gives back the value
    q7b = {<<5{d4}};
    `checkp(q7b, "'{'h4d, 'h77, 'h21, 'h6c}");
    {<<5{dd4}} = q7;
    `checkp(dd4, "'{'h9, 'hd, 'h8, 'h3, 'h9, 'hf, 'h3}");
    {<<5{d4b}} = q7;
    `checkp(d4b, "'{'h9, 'hd, 'h8, 'h3, 'h9, 'hf, 'h3}");
    // A fixed-size array source, of either range direction, streamed left to right
    begin
      automatic bit [6:0] f7[4] = '{7'h4d, 7'h77, 7'h21, 7'h6c};
      automatic bit [6:0] f7d[3:0] = '{7'h4d, 7'h77, 7'h21, 7'h6c};
      automatic byte fb[3] = '{8'h12, 8'h34, 8'h56};
      automatic logic [68:0] w69[2] = '{69'h1f_0123_4567_89ab_cdef, 69'h00_fedc_ba98_7654_3210};
      automatic bit [22:0] d23[$];
      {<<5{d4}} = f7;
      `checkp(d4, "'{'h9, 'hd, 'h8, 'h3, 'h9, 'hf, 'h3}");
      {<<5{d4}} = f7d;
      `checkp(d4, "'{'h9, 'hd, 'h8, 'h3, 'h9, 'hf, 'h3}");
      {<<4{d8}} = fb;
      `checkp(d8, "'{'h65, 'h43, 'h21}");
      {<<23{d23}} = w69;
      `checkp(d23, "'{'h543210, 'h7530ec, 'h3fb72, 'h2bcdef, 'hacf13, 'h7c048d}");
    end
    // Also into a stream of whole elements of another width, either direction
    begin
      automatic byte fb4[4] = '{8'h12, 8'h34, 8'h56, 8'h78};
      automatic byte fb4d[3:0] = '{8'h12, 8'h34, 8'h56, 8'h78};
      automatic bit [6:0] f7[4] = '{7'h4d, 7'h77, 7'h21, 7'h6c};
      automatic bit [15:0] h16[$];
      automatic bit [15:0] hb16[$:3];
      automatic bit [13:0] w14[];
      {>>{h16}} = fb4;
      `checkp(h16, "'{'h1234, 'h5678}");
      {>>{h16}} = fb4d;
      `checkp(h16, "'{'h1234, 'h5678}");
      {>>{hb16}} = fb4;
      `checkp(hb16, "'{'h1234, 'h5678}");
      {<<16{h16}} = fb4;
      `checkp(h16, "'{'h5678, 'h1234}");
      {>>{w14}} = f7;
      `checkp(w14, "'{'h26f7, 'h10ec}");
    end
    // Also of a multidimensional array, of any range directions, and into a bounded queue
    begin
      automatic byte sda[2:1][-4:-3] = '{'{8'h87, 8'h12}, '{8'h9a, 8'hcf}};
      automatic byte sad[0:1][1:0] = '{'{8'h87, 8'h12}, '{8'h9a, 8'hcf}};
      automatic byte sdd[1:0][1:0] = '{'{8'h87, 8'h12}, '{8'h9a, 8'hcf}};
      automatic byte s3[1:0][0:1][1:0] = '{
          '{'{8'h11, 8'h10}, '{8'h15, 8'h14}}, '{'{8'h01, 8'h00}, '{8'h05, 8'h04}}
      };
      automatic byte s4[4] = '{8'h87, 8'h12, 8'h9a, 8'hcf};
      automatic bit [15:0] h16[$];
      automatic bit [15:0] hb16[$:1];
      automatic bit [31:0] w32[$];
      automatic bit [3:0] n4[$];
      {>>{h16}} = sda;
      `checkp(h16, "'{'h8712, 'h9acf}");
      {>>{h16}} = sad;
      `checkp(h16, "'{'h8712, 'h9acf}");
      {>>{h16}} = sdd;
      `checkp(h16, "'{'h8712, 'h9acf}");
      {>>{w32}} = s3;
      `checkp(w32, "'{'h11101514, 'h1000504}");
      {<<8{h16}} = sad;
      `checkp(h16, "'{'hcf9a, 'h1287}");
      {<<4{n4}} = sdd;
      `checkp(n4, "'{'hf, 'hc, 'ha, 'h9, 'h2, 'h1, 'h7, 'h8}");
      {<<5{hb16}} = s4;
      `checkp(hb16, "'{'he754, 'ha790}");
    end
    d4 = '{};
    {<<5{d4}} <= q7;
    #1;
    `checkp(d4, "'{'h9, 'hd, 'h8, 'h3, 'h9, 'hf, 'h3}");
    // Slices of whole elements, and wider than the elements
    q8 = '{8'h12, 8'h34, 8'h56};
    {<<8{d8}} = q8;
    `checkp(d8, "'{'h56, 'h34, 'h12}");
    {<<16{d8}} = q8;
    `checkp(d8, "'{'h56, 'h12, 'h34}");
    {<<16{d4}} = q8;
    `checkp(d4, "'{'h5, 'h6, 'h1, 'h2, 'h3, 'h4}");
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
