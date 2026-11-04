// -*- mode: C++; c-file-style: "cc-mode" -*-
//*************************************************************************
//
// This program is free software; you can redistribute it and/or modify it
// under the terms of either the GNU Lesser General Public License Version 3
// or the Perl Artistic License Version 2.0.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: LGPL-3.0-only OR Artistic-2.0
//
//*************************************************************************

#include <sys/syscall.h>
#include <unistd.h>

// Replaces write(), as used for the solver's pipe, with one that writes at most a few bytes
// per call, as write() may
extern "C" ssize_t write(int fd, const void* bufp, size_t count) {
    static constexpr size_t MAX_BYTES = 7;
    return syscall(SYS_write, fd, bufp, count < MAX_BYTES ? count : MAX_BYTES);
}
