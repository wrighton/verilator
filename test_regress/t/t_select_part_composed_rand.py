#!/usr/bin/env python3
# DESCRIPTION: Verilator: Verilog Test driver/expect definition
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of either the GNU Lesser General Public License Version 3
# or the Perl Artistic License Version 2.0.
# SPDX-FileCopyrightText: 2026 Wilson Snyder
# SPDX-License-Identifier: LGPL-3.0-only OR Artistic-2.0

import random

import vltest_bootstrap

test.scenarios('vlt')

if test.tsan:
    test.skip("ThreadSanitizer not compatible with AddressSanitizer\n")

# Selects of members and parts of elements of packed arrays of structures at variable positions,
# from seeds that read past a value when guards are lost; the sanitizers report such a read
unique = test.name == "t_select_part_composed_rand_unique"
random.seed(14 if unique else 9)
test.top_filename = f"{test.obj_dir}/t.v"
lines = [
    "module t;", "  logic clk = 0;", "  int cyc = 0;",
    "  logic [63:0] crc = 64'h5aa5_0f0f_1234_9876;"
]
arrs = []
for a in range(8):
    fx = random.randint(3, 60)
    fy = random.randint(3, 40)
    lines.append(f"  typedef struct packed {{ logic [{fx-1}:0] x; logic [{fy-1}:0] y; }} s{a}_t;")
    ne = random.randint(2, 40)
    n2 = random.choice([None, None, random.randint(2, 4)])
    if n2:
        lines.append(f"  s{a}_t [{ne-1}:0][{n2-1}:0] a{a};")
        tot = ne * n2 * (fx + fy)
    else:
        if random.random() < 0.3:
            lines.append(f"  s{a}_t [0:{ne-1}] a{a};")
        else:
            lines.append(f"  s{a}_t [{ne-1}:0] a{a};")
        tot = ne * (fx + fy)
    arrs.append((a, fx, fy, ne, n2, tot))
for v in range(6):
    lines.append(f"  logic [{random.randint(2, 8)}:0] s{v};")
exprs = []
for e in range(48):
    a, fx, fy, ne, n2, tot = random.choice(arrs)
    s1 = f"s{random.randint(0, 5)}"
    s2 = f"s{random.randint(0, 5)}"
    s3 = f"s{random.randint(0, 5)}"
    base = f"a{a}[{s1}]" if not n2 else f"a{a}[{s1}][{s2}]"
    k = random.choice(["x", "y", "ypart", "elpart", "elbit", "xvar"])
    if k == "x":
        ex = f"{base}.x"
    elif k == "y":
        ex = f"{base}.y"
    elif k == "ypart":
        w = random.randint(1, fy)
        ex = f"{base}.y[{s3}+:{w}]"
    elif k == "xvar":
        w = random.randint(1, fx)
        ex = f"{base}.x[{s3}-:{w}]"
    elif k == "elpart":
        w = random.randint(1, min(30, fx + fy))
        ex = f"{base}[{s3}+:{w}]"
    else:
        ex = f"{base}[{s3}]"
    lines.append(f"  logic [63:0] r{e};")
    lines.append(f"  always_comb r{e} = 64'({ex});")
    exprs.append(e)
lines.append("  always #5 clk = ~clk;")
lines.append("  always @(posedge clk) begin")
lines.append("    crc <= {crc[62:0], crc[63] ^ crc[2] ^ crc[0]};")
for a, fx, fy, ne, n2, tot in arrs:
    lines.append(f"    a{a} <= {tot}'({{{(tot+63)//64}{{crc ^ 64'(cyc * 2654435761)}}}});")
for v in range(6):
    lines.append(f"    s{v} <= $bits(s{v})'(crc[{v*7}+:12]);")
lines.append("    $display(\"%0d " + " ".join(["%h"] * len(exprs)) + "\", cyc, " +
             ", ".join(f"r{e}" for e in exprs) + ");")
lines.append("    if (++cyc == 300) begin")
lines.append("      $write(\"*-* All Finished *-*\\n\");")
lines.append("      $finish;")
lines.append("    end")
lines.append("  end")
lines.append("endmodule")
with open(test.top_filename, "w", encoding="utf8") as f:
    f.write("\n".join(lines) + "\n")

test.compile(verilator_flags2=[
    "--binary", "-Wno-fatal", "--x-assign unique" if unique else "--x-assign fast",
    "-CFLAGS -fsanitize=address,undefined", "-CFLAGS -fno-sanitize-recover=undefined",
    "-LDFLAGS -fsanitize=address,undefined"
])

test.execute()

test.passes()
