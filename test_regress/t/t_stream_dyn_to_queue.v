// DESCRIPTION: Verilator: Verilog Test module
//
// A dynamic array or queue streamed into a queue of other elements takes the
// bits of the stream from the left, the last element zero-filled on the right
// (IEEE 1800-2023 11.4.14). A bounded queue keeps the elements within its
// bound, discarding the others with a warning (IEEE 1800-2023 7.10.5).
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkp(gotv,expv_s) do begin string gotv_s; gotv_s = $sformatf("%p", gotv); if ((gotv_s) != (expv_s)) begin $write("%%Error: %s:%0d:  got='%s' exp='%s'\n", `__FILE__,`__LINE__, (gotv_s), (expv_s)); `stop; end end while(0);
// verilog_format: on

module t;
  typedef bit [3:0] nibble_q_t[$];

  initial begin
    bit [3:0] dyn4[];
    nibble_q_t q4;
    byte unsigned q8[$];
    bit [10:0] q11[$];
    bit [5:0] room6[$:1];
    bit [5:0] short6[$:0];
    bit [6:0] bound7[$:1];
    for (int i = 0; i < 2; ++i) begin
      dyn4 = '{4'(i + 1), 4'(i + 2), 4'(i + 3)};
      q4 = '{4'(i + 4), 4'(i + 5)};
      q8 = {>>{dyn4}};  // Dynamic array into a queue
      `checkp(q8, i == 0 ? "'{'h12, 'h30}" : "'{'h23, 'h40}");
      q8 = {>>{q4}};  // Queue of a typedef into a queue
      `checkp(q8, i == 0 ? "'{'h45}" : "'{'h56}");
      q11 = {>>{dyn4}};
      `checkp(q11, i == 0 ? "'{'h91, 'h400}" : "'{'h11a, 'h0}");
      q4 = {>>{q11}};  // Wider elements into narrower
      `checkp(q4, i == 0 ? "'{'h1, 'h2, 'h3, 'h0, 'h0, 'h0}" : "'{'h2, 'h3, 'h4, 'h0, 'h0, 'h0}");
      bound7 = '{7'h56 + 7'(i)};
      room6 = {>>{bound7}};  // Bounded source and destination, within the bound
      `checkp(room6, i == 0 ? "'{'h2b, 'h0}" : "'{'h2b, 'h20}");
      room6 = {<<{bound7}};
      `checkp(room6, i == 0 ? "'{'h1a, 'h20}" : "'{'h3a, 'h20}");
      short6 = {>>{bound7}};  // Beyond the bound
      `checkp(short6, "'{'h2b}");
    end
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
