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
