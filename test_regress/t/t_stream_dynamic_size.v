// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Streaming assignments whose stream is only sized at run time: a warning when the stream does
// not fit the target as IEEE 1800-2023 11.4.14 requires, whose result is not checked, also when
// the result is never read, and none otherwise

module t;
  typedef byte byte_q_t[$];

  // A queue of the bytes 1, 2, ..., n
  function automatic byte_q_t bytes(int n);
    for (int i = 0; i < n; ++i) bytes.push_back(byte'(i + 1));
  endfunction

  int n;

  initial begin
    int j;
    shortint h;
    bit [15:0] p16;
    byte f[2];
    byte q[$];
    byte dq[$];
    bit [11:0] p12;
    bit [11:0] s12[$];
    int d[];
    bit [99:0] w100[$];
    bit [199:0] w200;
    // Sizes known only at run time
    n = $urandom_range(4, 4);
    p12 = 12'(n * 'h177);

    // Into a fixed-size target: a stream as wide fits, a narrower one is widened with zeros, a
    // wider one warns
    q = bytes(n);
    j = {>>{q}};
    `checkh(j, 32'h01020304);
    q = bytes(n - 3);
    f = {>>{q}};
    `checkh(f[0], 8'h01);
    `checkh(f[1], 8'h00);
    if (n == 4) j = {>>{q}};  // Alike branches, which are not merged
    else j = {>>{q}};
    `checkh(j, 32'h01000000);
    q = bytes(n + 1);
    j = {>>{q}};
    j = {<<8{q}};
    j <= {>>{q}};
    q = bytes(n - 1);
    f = {>>{q}};
    d = new[n - 2];
    j = {>>{d}};
    w100 = {100'(n), 100'(n), 100'(n)};
    w200 = {>>{w100}};

    // Unpacked from a source: a longer source gives its leftmost bits, a shorter one warns
    q = bytes(n + 2);
    {>>{j}} = q;
    `checkh(j, 32'h01020304);
    {>>{f}} = q;
    `checkh(f[0], 8'h01);
    `checkh(f[1], 8'h02);
    {>>{p16}} = {>>{q}};
    `checkh(p16, 16'h0102);
    q = bytes(n - 2);
    {>>{j}} = q;
    q = bytes(n - 3);
    {>>{f}} = q;
    {>>{p16}} = {>>{q}};
    q = bytes(n + 1);
    {>>{h, j}} = q;  // Warns once for its several targets

    // Unpacked into a queue: a source of whole elements fits, a partial one warns
    s12 = {p12, p12};
    {>>{dq}} = s12;
    `checkh(dq.size(), 3);
    `checkh(dq[0], 8'h5d);
    `checkh(dq[1], 8'hc5);
    `checkh(dq[2], 8'hdc);
    s12 = {p12};
    {>>{dq}} = s12;
    {>>{dq}} = p12;
    {<<4{dq}} = p12;

    // Streamed into a queue, a stream that is not a whole number of elements is widened with
    // zeros, with no warning
    dq = {>>{p12}};
    `checkh(dq.size(), 2);
    `checkh(dq[0], 8'h5d);
    `checkh(dq[1], 8'hc0);
    dq = {>>{s12}};
    `checkh(dq.size(), 2);
    `checkh(dq[0], 8'h5d);
    `checkh(dq[1], 8'hc0);

    #1;
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
