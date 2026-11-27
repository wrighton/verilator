// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got='h%x exp='h%x\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

interface wb_ifc;
  logic clk;
  wire rst;
  tri0 cyc;
  clocking mck @(posedge clk);
    input rst;
    output cyc;
  endclocking
endinterface

// The initializer of an output clockvar reads its net, it does not drive it
interface pull_ifc (
    input logic clk
);
  tri1 [6:0] v;
  tri0 [6:0] w;
  clocking cb @(posedge clk);
    output v, w;
  endclocking
endinterface

// Clocking block outputs of interface nets also driven from outside, by an assignment that
// can drive 'z.
interface net_ifc #(
    parameter int K = 0
) (
    input logic clk
);
  wire [32:0] v;
  clocking cb @(posedge clk);
    output v;
  endclocking
  modport drv_mp(clocking cb);
endinterface

module net_wrap #(
    parameter int K = 0
) (
    input logic clk,
    input logic en,
    input logic [32:0] d
);
  net_ifc #(K) ni (clk);
  assign ni.v = en ? d : 'z;
endmodule

module net_mp_drv (
    net_ifc.drv_mp p
);
  task automatic drive_one();
    p.cb.v[0] <= 1'b1;
  endtask
endmodule

class net_src;
  logic [32:0] val;
endclass

class net_drv #(
    parameter int K = 0
);
  virtual net_ifc #(K) vif;
  logic [32:0] data;
  function new(virtual net_ifc #(K) i);
    vif = i;
  endfunction
  task drive();
    vif.cb.v <= data;
  endtask
  function void get_mask(output logic [32:0] m);
    m = 33'h1_ffff_00ff;
  endfunction
  function logic [32:0] masked();
    logic [32:0] m;
    get_mask(m);
    return data & m;
  endfunction
  task drive_masked();
    vif.cb.v <= masked();
  endtask
  task drive_from(net_src src);
    vif.cb.v <= src.val;
  endtask
endclass

interface skew_ifc (
    input logic clk
);
  wire [6:0] v;
  clocking cb @(posedge clk);
    output #2 v;
  endclocking
endinterface

// A clocking block output of a net also driven 'z from outside, by a module, driving a
// four-state variable
interface sub_ifc (
    input logic clk
);
  wire v;
  clocking cb @(posedge clk);
    output v;
  endclocking
endinterface

module sub_wrap (
    input logic clk,
    input wire p
);
  logic act = 0;
  sub_ifc s (clk);
  assign s.v = act ? 1'bz : p;
endmodule

// Clocking block outputs of nets also driven 'z from outside
interface fb_ifc #(
    parameter int K = 0
) (
    input logic clk
);
  wire [3:0] d;
  wire [3:0] rel;
  assign rel = 'z;
  clocking cb @(posedge clk);
    output d;
  endclocking
endinterface

class fb_drv #(
    parameter int K = 2
);
  virtual fb_ifc #(K) vif;
  task release_d();
    vif.cb.d <= vif.rel;
  endtask
endclass

// Clocking block drives in the interface of a net also driven 'z from outside, of values with 'z
interface own_z_ifc (
    input logic clk
);
  wire [3:0] v;
  clocking cb @(posedge clk);
    output v;
  endclocking
  initial begin
    @(negedge clk);
    cb.v <= 4'b01zz;
    @(posedge clk);
    #1;
    `checkh(v[1:0], 2'bzz);
  end
endinterface

// A net tristate in its interface and nets driven 'z from outside, all with output skews
interface skew_mix_ifc (
    input logic clk
);
  tri1 [1:0] a;
  wire [1:0] a0;
  wire [1:0] a1;
  wire [1:0] a2;
  clocking cb @(posedge clk);
    output #1 a, a0, a1, a2;
  endclocking
  initial begin
    @(negedge clk);
    cb.a <= 2'b01;
  end
endinterface

// A clocking block output whose target is a select of a net
interface sel_ifc (
    input logic clk
);
  wire [3:0] v;
  clocking cb @(posedge clk);
    output o = v[1:0];
  endclocking
endinterface

// Two instances of one interface
interface shared_ifc (
    input logic clk
);
  wire [3:0] v;
  clocking cb @(posedge clk);
    output v;
  endclocking
endinterface

// A clocking block output driven in a class through a virtual interface from a variable of the
// interface written from a net
interface q_ifc (
    input logic clk,
    input logic [3:0] x
);
  wire [3:0] v;
  wire [3:0] w;
  logic [3:0] q;
  assign w = x;
  assign q = w;
  clocking cb @(posedge clk);
    output v;
  endclocking
endinterface

// A variable written by a clocking block output, and with 'z by another module
interface var_cb_ifc (
    input logic clk
);
  logic [3:0] v;
  clocking cb @(posedge clk);
    output v;
  endclocking
endinterface

module var_drv (
    var_cb_ifc i,
    input logic clk,
    input logic en
);
  always @(negedge clk) if (en) i.v = 4'b10zz;
endmodule

class fbz_drv;
  virtual fb_ifc #(16) vif;
  task release_d();
    vif.cb.d <= 'z;
  endtask
endclass

class q_drv;
  virtual q_ifc vif;
  task drive_q();
    vif.cb.v <= vif.q;
  endtask
endclass

module t;
  wb_ifc wb_ma ();
  int pending = 0;  // Test blocks running

  logic clk = 0;
  always #5 clk = ~clk;

  // Bits of a value that are driven, the others 'z
  function automatic logic [32:0] driven(logic [32:0] v, logic [32:0] en);
    for (int i = 0; i < 33; ++i) driven[i] = en[i] ? v[i] : 1'bz;
  endfunction

  // Test: pulled nets with clocking outputs before and after the first drive
  pull_ifc ip (clk);
  initial begin
    logic [6:0] d;
    ++pending;
    #1;
    `checkh(ip.v, 7'h7f);
    `checkh(ip.w, 7'h00);
    repeat (3) begin
      @(negedge clk);
      d = 7'($random);
      ip.cb.v <= d;
      ip.cb.w <= ~d;
      @(posedge clk);
      #1;
      `checkh(ip.v, d);
      `checkh(ip.w, ~d);
    end
    --pending;
  end

  // Test: clocking block output of a net also driven from outside: 'z until the first drive,
  // drives at the clocking event of constants, of four-state and two-state variables and of a
  // conditional value that may be 'z, the last of two drives, and a 'z drive releasing the net
  logic n_en = 1;
  logic [32:0] n_d = 33'h1_2345_6789;
  net_wrap nw (
      clk,
      n_en,
      n_d
  );
  initial begin
    logic [32:0] lv;
    bit [32:0] bv;
    logic [32:0] exp_v;
    logic [32:0] exp_en;
    logic [32:0] prev;
    logic [32:0] prev_en;
    ++pending;
    #1;
    `checkh(nw.ni.v, n_d);
    n_en = 0;
    #1;
    `checkh(nw.ni.v, 33'bz);
    prev_en = '0;
    for (int n = 0; n < 12; ++n) begin
      @(negedge clk);
      lv = 33'({$random, $random});
      bv = 33'({$random, $random});
      exp_en = '1;
      case (n % 4)
        0: begin
          nw.ni.cb.v <= 33'h0_5555_aaaa;
          exp_v = 33'h0_5555_aaaa;
        end
        1: begin
          nw.ni.cb.v <= lv;
          exp_v = lv;
        end
        2: begin
          nw.ni.cb.v <= bv;
          exp_v = bv;
        end
        default: begin
          nw.ni.cb.v <= n[3] ? lv : 'z;
          exp_v = lv;
          exp_en = n[3] ? '1 : '0;
        end
      endcase
      // A later change of a variable does not change the drive
      lv = ~lv;
      #1;
      `checkh(nw.ni.v, driven(prev, prev_en));
      @(posedge clk);
      #1;
      `checkh(nw.ni.v, driven(exp_v, exp_en));
      prev = exp_v;
      prev_en = exp_en;
    end
    @(negedge clk);
    nw.ni.cb.v <= 33'h1;
    nw.ni.cb.v <= 33'h2;
    @(posedge clk);
    #1;
    `checkh(nw.ni.v, 33'h2);
    @(negedge clk);
    nw.ni.cb.v <= 'z;
    @(posedge clk);
    #1;
    `checkh(nw.ni.v, 33'bz);
    n_en = 1;
    n_d = 33'h1_0f0f_0f0f;
    #1;
    `checkh(nw.ni.v, n_d);
    n_en = 0;
    @(negedge clk);
    nw.ni.cb.v <= 33'h7;
    @(posedge clk);
    #1;
    `checkh(nw.ni.v, 33'h7);
    --pending;
  end

  // Test: drives of some bits, also through a modport, leave the other driven bits as they
  // were; a drive with a cycle delay, of a variable changed after the drive, or with an output
  // skew is applied when it matures; drives through a virtual interface of a class field, also
  // of a value with side effects and of a field of an object
  logic k_en = 0;
  logic [32:0] k_d = 33'h1_ffff_0000;
  net_wrap #(1) kp (
      clk,
      k_en,
      k_d
  );
  net_mp_drv kpm (kp.ni);
  net_wrap #(3) kc (
      clk,
      k_en,
      k_d
  );
  net_wrap #(4) kv (
      clk,
      k_en,
      k_d
  );
  skew_ifc ks (clk);
  logic ks_en = 0;
  assign ks.v = ks_en ? 7'h11 : 'z;
  initial begin
    net_drv #(4) drv;
    net_src src;
    logic [32:0] q;
    ++pending;
    drv = new(kv.ni);
    src = new;
    @(negedge clk);
    kp.ni.cb.v[4:1] <= 4'ha;
    q = 33'h1_2345_6789;
    kc.ni.cb.v <= ##2 q;
    q = 33'h0_9876_5432;
    drv.data = 33'h0_0bad_cafe;
    drv.drive();
    ks.cb.v <= 7'h5a;
    @(posedge clk);
    #1;
    // Before the skew
    `checkh(ks.v, 7'bz);
    #2;
    `checkh(kp.ni.v[4:1], 4'ha);
    `checkh(kv.ni.v, 33'h0_0bad_cafe);
    `checkh(ks.v, 7'h5a);
    @(negedge clk);
    kpm.drive_one();
    ks.cb.v <= 7'h25;
    @(posedge clk);
    #1;
    `checkh(ks.v, 7'h5a);
    #2;
    `checkh(kp.ni.v[4:0], 5'h15);
    `checkh(kc.ni.v, 33'h1_2345_6789);
    `checkh(ks.v, 7'h25);
    @(negedge clk);
    drv.data = 33'h0_1234_5678;
    drv.drive_masked();
    @(posedge clk);
    #1;
    `checkh(kv.ni.v, 33'h0_1234_0078);
    @(negedge clk);
    src.val = 33'h1_0000_1111;
    drv.drive_from(src);
    @(posedge clk);
    #1;
    `checkh(kv.ni.v, 33'h1_0000_1111);
    // The other drivers
    k_en = 1;
    #1;
    `checkh(kp.ni.v[32:5], k_d[32:5]);
    --pending;
  end

  // Test: a clocking block output of a net driven 'z by a module, driving a four-state
  // variable from the top
  wire s_p;
  sub_wrap sw (
      clk,
      s_p
  );
  logic s_d = 1;
  int s_seen = 0;
  always @(posedge clk) if (sw.s.v === 1'b1) ++s_seen;
  initial begin
    ++pending;
    #1 sw.act = 1;
    @(sw.s.cb);
    sw.s.cb.v <= s_d;
    repeat (3) @(sw.s.cb);
    sw.s.cb.v <= 1'b0;
    #50;
    `checkh(s_seen, 3);
    --pending;
  end

  // Test: drives of nets also driven 'z from outside: in a task, of a net; in a class, of a net
  // through a virtual interface; and of a variable that is 'z
  logic f_en = 0;
  fb_ifc #(1) f1 (clk);
  fb_ifc #(2) f2 (clk);
  fb_ifc #(6) f6 (clk);
  assign f1.d = f_en ? 4'h3 : 'z;
  assign f2.d = f_en ? 4'h3 : 'z;
  assign f6.d = f_en ? 4'h3 : 'z;
  wire [3:0] f_rel = 'z;
  task automatic release_f1();
    f1.cb.d <= f_rel;
  endtask
  initial begin
    fb_drv drv;
    logic [3:0] q;
    ++pending;
    drv = new;
    drv.vif = f2;
    q = 'z;
    @(negedge clk);
    release_f1();
    drv.release_d();
    f6.cb.d <= q;
    repeat (2) @(posedge clk);
    #1;
    `checkh(f1.d, 4'bz);
    `checkh(f2.d, 4'bz);
    `checkh(f6.d, 4'bz);
    f_en = 1;
    #1;
    `checkh(f1.d, 4'h3);
    `checkh(f2.d, 4'h3);
    `checkh(f6.d, 4'h3);
    --pending;
  end

  // Test: drives in the interface of values with 'z; a 'z drive, then a cycle-delayed drive of a
  // net that is 'z; nets with output skews, tristate in their interface or from outside
  logic m_en = 0;
  own_z_ifc oz (clk);
  assign oz.v = m_en ? 4'h8 : 'z;
  fb_ifc #(18) fc (clk);
  assign fc.d = m_en ? 4'h3 : 'z;
  wire [3:0] m_src = m_en ? 4'ha : 'z;
  skew_mix_ifc sm (clk);
  assign sm.a0 = m_en ? 2'b10 : 'z;
  assign sm.a1 = m_en ? 2'b10 : 'z;
  initial begin
    ++pending;
    @(negedge clk);
    fc.cb.d <= 'z;
    @(negedge clk);
    fc.cb.d <= ##1 m_src;
    sm.cb.a0 <= 2'b01;
    sm.cb.a1 <= 2'b01;
    sm.cb.a2 <= 2'b01;
    #7;
    `checkh(sm.a, 2'b01);
    `checkh(sm.a0, 2'b01);
    `checkh(sm.a1, 2'b01);
    `checkh(sm.a2, 2'b01);
    repeat (2) @(posedge clk);
    #1;
    `checkh(fc.d, 4'bz);
    --pending;
  end

  // Test: two instances of one interface, one driven by a value that may be 'z, the other in a
  // task
  logic sh_oe = 0;
  logic sh_sel = 1;
  shared_ifc sh_a (clk);
  shared_ifc sh_b (clk);
  assign sh_a.v = sh_oe ? 4'h3 : 'z;
  assign sh_b.v = sh_oe ? 4'h3 : 'z;
  task automatic drive_sh_b();
    sh_b.cb.v <= 4'h5;
  endtask
  initial begin
    ++pending;
    @(negedge clk);
    sh_a.cb.v <= sh_sel ? 4'h6 : 'z;
    drive_sh_b();
    @(posedge clk);
    #1;
    `checkh(sh_a.v, 4'h6);
    `checkh(sh_b.v, 4'h5);
    --pending;
  end

  // Test: a clocking block output whose target is a select of a net also driven 'z from outside
  logic se_en = 0;
  sel_ifc se (clk);
  assign se.v = se_en ? 4'b1010 : 'z;
  initial begin
    ++pending;
    @(negedge clk);
    se.cb.o <= 2'b01;
    @(posedge clk);
    #1;
    `checkh(se.v[1:0], 2'b01);
    se_en = 1;
    #1;
    `checkh(se.v[3:2], 2'b10);
    --pending;
  end

  // Test: a 'z drive in a class through a virtual interface, after a drive of the output in the
  // interface's module
  fb_ifc #(16) fz (clk);
  logic fz_en = 0;
  assign fz.d = fz_en ? 4'h3 : 'z;
  initial begin
    fbz_drv drv;
    ++pending;
    drv = new;
    drv.vif = fz;
    @(negedge clk);
    fz.cb.d <= 4'ha;
    @(posedge clk);
    #1;
    `checkh(fz.d, 4'ha);
    @(negedge clk);
    drv.release_d();
    @(posedge clk);
    #1;
    `checkh(fz.d, 4'bz);
    fz_en = 1;
    #1;
    `checkh(fz.d, 4'h3);
    --pending;
  end

  // Test: a drive in a class through a virtual interface from a variable written from a net
  logic q_en = 0;
  q_ifc qi (
      clk,
      4'h3
  );
  assign qi.v = q_en ? 4'h5 : 'z;
  initial begin
    q_drv drv;
    ++pending;
    drv = new;
    drv.vif = qi;
    @(negedge clk);
    drv.drive_q();
    @(posedge clk);
    #1;
    `checkh(qi.v, 4'h3);
    q_en = 1;
    #1;
    // The bits where the two drivers agree
    `checkh(qi.v[3], 1'b0);
    `checkh(qi.v[0], 1'b1);
    --pending;
  end

  // Test: a clocking block output of a variable still drives it after another module wrote the
  // variable with 'z
  logic vc_en = 0;
  var_cb_ifc vc (clk);
  var_drv u_vc (
      vc,
      clk,
      vc_en
  );
  initial begin
    ++pending;
    @(negedge clk);
    vc.cb.v <= 4'h3;
    @(posedge clk);
    #1;
    `checkh(vc.v, 4'h3);
    vc_en = 1;
    @(negedge clk);
    #1;
    vc_en = 0;
    vc.cb.v <= 4'h6;
    @(posedge clk);
    #1;
    `checkh(vc.v, 4'h6);
    --pending;
  end

  initial begin
    #1;
    wait (pending == 0);
    $write("*-* All Finished *-*\n");
    $finish;
  end
endmodule
