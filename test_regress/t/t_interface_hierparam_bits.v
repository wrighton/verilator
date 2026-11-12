// DESCRIPTION: Verilator: Verilog Test module
//
// $bits() of interface member signals used as a child module parameter value.
// $bits reads the type, not the hierarchical value, so it is legal in a
// parameter (IEEE 1800-2023 6.20.2 forbids hierarchical values only).
// Also when the interface port is connected to a hierarchical reference.
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0)
// verilog_format: on

interface axi_if #(
    parameter int ID_W = 8,
    parameter int ADDR_W = 32
);
  logic [ID_W-1:0] AWID;
  logic [ADDR_W-1:0] AWADDR;
  logic [7:0] AWLEN;
endinterface

module chkmod #(
    parameter int PAYLOAD_WIDTH = 1,
    parameter int EXPECT = 1
);
  initial `checkh(PAYLOAD_WIDTH, EXPECT);
endmodule

module bridge #(
    parameter int EXPECT = 1
) (
    axi_if axi
);
  // $bits of a concat of interface members
  chkmod #(
      .PAYLOAD_WIDTH($bits({axi.AWID, axi.AWADDR, axi.AWLEN})),
      .EXPECT(EXPECT)
  ) u_concat ();
  // $bits of a single interface member
  chkmod #(
      .PAYLOAD_WIDTH($bits(axi.AWADDR)),
      .EXPECT(EXPECT - 12 - 8)
  ) u_single ();
  // $bits of an interface member in a generate condition
  if ($bits(axi.AWID) != 12) begin : g_bad
    $error("Wrong interface parameters in generate condition");
  end
endmodule

// Interface instances reached by hierarchical references as interface port actuals
interface harness #(
    parameter int ADDR_W = 32
);
  axi_if #(
      .ID_W(12),
      .ADDR_W(ADDR_W)
  ) axi ();
endinterface

interface outer;
  harness #(.ADDR_W(24)) h ();
endinterface

module holder #(
    parameter int ADDR_W = 40
);
  axi_if #(
      .ID_W(12),
      .ADDR_W(ADDR_W)
  ) axi ();
endmodule

module bind_target;
endmodule

module port_holder (
    axi_if src
);
  axi_if #(
      .ID_W(12),
      .ADDR_W($bits(src.AWADDR))
  ) axi ();
endmodule

module chain_holder;
  harness h ();
  port_holder p (.src(h.axi));
endmodule

module local_holder #(
    parameter int ADDR_W = 32
);
  axi_if #(
      .ID_W(12),
      .ADDR_W(ADDR_W)
  ) axi ();
  port_holder p (.src(axi));
endmodule

module cycle_holder (
    axi_if src
);
  axi_if axi ();
endmodule

module fan_holder (
    axi_if s0,
    axi_if s1
);
  axi_if #(
      .ID_W(12),
      .ADDR_W($bits(s0.AWADDR) + $bits(s1.AWADDR) - 16)
  ) axi ();
endmodule

interface outer_p #(
    parameter int ADDR_W = 32
);
  harness #(.ADDR_W(ADDR_W)) h ();
endinterface

module mid_outer (
    outer_p o
);
  bridge #(.EXPECT(34)) dut (.axi(o.h.axi));
endmodule

interface wrap_if #(
    parameter int EXPECT = 1
) (
    axi_if axi
);
  if ($bits({axi.AWID, axi.AWADDR, axi.AWLEN}) != EXPECT) begin : g_bad
    $error("Wrong interface parameters in generate condition");
  end
endinterface

module mid (
    harness h
);
  // Through an interface port
  bridge #(.EXPECT(68)) dut (.axi(h.axi));
endmodule

bind bind_target harness #(.ADDR_W(20)) h ();

module t;
  axi_if #(
      .ID_W(12),
      .ADDR_W(64)
  ) if0 ();  // 12 + 64 + 8 = 84
  axi_if #(
      .ID_W(12),
      .ADDR_W(16)
  ) if1 ();  // 12 + 16 + 8 = 36

  bridge #(.EXPECT(84)) dut0 (.axi(if0));
  bridge #(.EXPECT(36)) dut1 (.axi(if1));
  axi_if #(
      .ID_W(12),
      .ADDR_W(16)
  ) ifs[2] ();
  bridge #(.EXPECT(36)) dut1s (.axi(ifs[1]));

  // Instances of the referenced interfaces are below this module (IEEE 1800-2023 25.3)
  bridge #(.EXPECT(52)) dut2 (.axi(h0.axi));
  harness h0 ();  // 12 + 32 + 8 = 52
  harness #(.ADDR_W(48)) h1 ();  // 12 + 48 + 8 = 68
  bridge #(.EXPECT(68)) dut3 (.axi(h1.axi));
  outer o ();  // 12 + 24 + 8 = 44
  bridge #(.EXPECT(44)) dut4 (.axi(o.h.axi));
  holder m0 ();  // 12 + 40 + 8 = 60
  bridge #(.EXPECT(60)) dut5 (.axi(m0.axi));
  bridge #(.EXPECT(30)) dut6 (.axi(m1.axi));
  holder #(.ADDR_W(10)) m1 ();  // 12 + 10 + 8 = 30
  bridge #(.EXPECT(42)) dut7 (.axi(m2.axi));
  holder m2 ();
  defparam m2.ADDR_W = 22;  // 12 + 22 + 8 = 42
  bind_target b ();  // 12 + 20 + 8 = 40
  bridge #(.EXPECT(40)) dut8 (.axi(b.h.axi));
  mid u_mid (.h(h1));
  bridge #(.EXPECT(36)) dut9 (.axi(p.axi));
  port_holder p (.src(if1));  // 12 + 16 + 8 = 36
  bridge #(.EXPECT(52)) dut10 (.axi(c.p.axi));
  chain_holder c ();  // 12 + 32 + 8 = 52
  // An interface instance, specialized while visiting this module
  wrap_if #(.EXPECT(52)) w (.axi(h0.axi));
  // Rooted at the module's name, so not resolved below it
  bridge #(.EXPECT(84)) dut11 (.axi(t.if0));
  bridge #(.EXPECT(38)) dut14 (.axi(lh.p.axi));
  local_holder #(.ADDR_W(18)) lh ();  // 12 + 18 + 8 = 38
  // Several references through the same instances
  bridge #(.EXPECT(36)) dut13 (.axi(f0.axi));
  fan_holder f0 (.s0(f1.axi), .s1(f1.axi));  // 12 + 16 + 8 = 36
  fan_holder f1 (.s0(f2.axi), .s1(f2.axi));
  fan_holder f2 (.s0(f3.axi), .s1(f3.axi));
  fan_holder f3 (.s0(if1), .s1(if1));
  // Through an interface specialization instantiated more than once
  outer_p #(.ADDR_W(14)) op0 ();  // 12 + 14 + 8 = 34
  outer_p #(.ADDR_W(14)) op1 ();
  mid_outer u_mid_o0 (.o(op0));
  mid_outer u_mid_o1 (.o(op1));
  // Instances connected to each other, left to be specialized in their turn
  cycle_holder y0 (.src(y1.axi));
  cycle_holder y1 (.src(y0.axi));
  if (1) begin : g
    harness #(.ADDR_W(30)) h0 ();  // 12 + 30 + 8 = 50
    bridge #(.EXPECT(50)) dut (.axi(h0.axi));
    if (1) begin : g2
      bridge #(.EXPECT(50)) dut (.axi(h0.axi));
    end
    bridge #(.EXPECT(50)) dut_p (.axi(p.axi));
    port_holder p (.src(h0.axi));
  end

  initial begin
    #1;
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
