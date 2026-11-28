// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// A streaming concatenation connected to an unpacked array port, as the
// continuous assignment of its bits to or from the port (IEEE 1800-2023
// 11.4.14, 23.3.3).

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
`define checkp(gotv,expv_s) do begin string gotv_s; gotv_s = $sformatf("%p", gotv); if ((gotv_s) != (expv_s)) begin $write("%%Error: %s:%0d:  got='%s' exp='%s'\n", `__FILE__,`__LINE__, (gotv_s), (expv_s)); `stop; end end while(0);
// verilog_format: on

module sub (
    input byte ia[4],
    input bit [6:0] id[2:0],
    output byte oa[2],
    output bit [6:0] od[1:0]
);
  assign oa = '{ia[0], ia[3]};
  assign od = '{id[2], id[0]};
endmodule

module recv (
    input bit [7:0] ia[2]
);
endmodule

module t;
  byte q[$];
  bit [31:0] p32;
  bit [20:0] p21;
  byte rq[$];
  bit [15:0] r16;
  bit [13:0] r14;
  byte qa[4];
  bit [6:0] da[2:0];
  byte oa[2];
  bit [6:0] od[1:0];

  // A queue and a packed value streamed into input arrays, output arrays
  // unpacked into a queue and a packed value
  sub u_queue (
      .ia({>>{q}}),
      .id({<<7{p21}}),
      .oa({>>{rq}}),
      .od({>>{r14}})
  );
  // A packed value streamed into an input array, output arrays unpacked into
  // left streams of packed values
  sub u_packed (
      .ia({<<8{p32}}),
      .id({>>{p21}}),
      .oa({<<8{r16}}),
      .od(od)
  );
  // Port arrays read back as connected
  sub u_plain (
      .ia(qa),
      .id(da),
      .oa(oa),
      .od()
  );

  // A narrower stream is left-justified in the port, and a stream of several operands, one a
  // queue, is connected as its assignment would be (IEEE 1800-2023 11.4.14)
  bit [7:0] x8;
  byte mq[$];
  recv u_narrow (.ia({>>{x8}}));
  recv u_mixed (.ia({>>{8'h12, mq}}));

  initial begin
    x8 = 8'h9a;
    mq = '{8'h34};
    q = '{8'h11, 8'h22, 8'h33, 8'h44};
    p32 = 32'h01020304;
    p21 = {7'h12, 7'h34, 7'h56};
    #1;
    `checkp(u_queue.ia, "'{'h11, 'h22, 'h33, 'h44}");
    `checkh(u_queue.id[2], 7'h56);
    `checkh(u_queue.id[1], 7'h34);
    `checkh(u_queue.id[0], 7'h12);
    `checkp(rq, "'{'h11, 'h44}");
    `checkh(r14, {7'h56, 7'h12});
    `checkp(u_packed.ia, "'{'h4, 'h3, 'h2, 'h1}");
    `checkh(u_packed.id[2], 7'h12);
    `checkh(u_packed.id[0], 7'h56);
    `checkh(r16, 16'h0104);
    `checkh(od[1], 7'h12);
    `checkh(od[0], 7'h56);
    `checkp(u_narrow.ia, "'{'h9a, 'h0}");
    `checkp(u_mixed.ia, "'{'h12, 'h34}");
    qa = '{8'h55, 8'h66, 8'h77, 8'h88};
    #1;
    `checkp(oa, "'{'h55, 'h88}");
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
