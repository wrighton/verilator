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

// Resident set size in kB, or 0 if the system does not report it
static long rssKb() {
    FILE* const fp = fopen("/proc/self/status", "r");
    if (!fp) return 0;
    char line[256];
    long kb = 0;
    while (fgets(line, sizeof(line), fp)) {
        if (!strncmp(line, "VmRSS:", 6)) kb = atol(line + 6);
    }
    fclose(fp);
    return kb;
}

static void makeRunDestroy() {
    const std::unique_ptr<VerilatedContext> contextp{new VerilatedContext};
    contextp->quiet(true);
    const std::unique_ptr<VM_PREFIX> topp{new VM_PREFIX{contextp.get(), "top"}};
    while (!contextp->gotFinish()) {
        topp->eval();
        if (!topp->eventsPending()) break;
        contextp->time(topp->nextTimeSlot());
    }
}

int main(int argc, char** argv) {
    static constexpr int WARMUP = 3;
    static constexpr int MODELS = 20;
    for (int i = 0; i < WARMUP; ++i) makeRunDestroy();
    const long startKb = rssKb();
    for (int i = 0; i < MODELS; ++i) makeRunDestroy();
    const long growthKb = rssKb() - startKb;
    printf("Memory growth over %d models %ld kB\n", MODELS, growthKb);
#if defined(__SANITIZE_ADDRESS__) || __has_feature(address_sanitizer)
    // AddressSanitizer quarantines freed memory, so resident memory does not follow live objects
    printf("Memory bound not checked under AddressSanitizer\n");
#else
    // Each model holds a 1 MB object in the process waiting at the join
    if (growthKb > MODELS * 1024 / 4) {
        vl_fatal(__FILE__, __LINE__, "top", "Memory grew with models destroyed");
    }
#endif
    printf("*-* All Finished *-*\n");
    return 0;
}
