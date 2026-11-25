// -*- mode: C++; c-file-style: "cc-mode" -*-
//
// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

#include <verilated.h>

#include <cstdio>
#include <cstring>
#include <memory>
#include VM_PREFIX_INCLUDE

#ifndef __has_feature
#define __has_feature(x) 0
#endif

// Peak resident set size in kB, or 0 if the system does not report it
static long peakRssKb() {
    FILE* const fp = fopen("/proc/self/status", "r");
    if (!fp) return 0;
    char line[256];
    long kb = 0;
    while (fgets(line, sizeof(line), fp)) {
        if (!strncmp(line, "VmHWM:", 6)) kb = atol(line + 6);
    }
    fclose(fp);
    return kb;
}

int main(int argc, char** argv) {
    const std::unique_ptr<VerilatedContext> contextp{new VerilatedContext};
    contextp->commandArgs(argc, argv);
    const std::unique_ptr<VM_PREFIX> topp{new VM_PREFIX{contextp.get(), "top"}};

    const long startKb = peakRssKb();
    while (!contextp->gotFinish()) {
        topp->eval();
        if (!topp->eventsPending()) break;
        contextp->time(topp->nextTimeSlot());
    }
    const long growthKb = peakRssKb() - startKb;
    printf("Peak memory growth %ld kB\n", growthKb);
#if defined(__SANITIZE_ADDRESS__) || __has_feature(address_sanitizer)
    // AddressSanitizer quarantines freed memory, so peak memory does not follow live objects
    printf("Memory bound not checked under AddressSanitizer\n");
#else
    // 2000 transactions of 16 kB each were sent; only a few may be live at once
    if (growthKb > 4096) vl_fatal(__FILE__, __LINE__, "top", "Memory grew with transactions sent");
#endif

    topp->final();
    return 0;
}
