// -*- mode: C++; c-file-style: "cc-mode" -*-
//*************************************************************************
//
// Code available from: https://verilator.org
//
// This program is free software; you can redistribute it and/or modify it
// under the terms of either the GNU Lesser General Public License Version 3
// or the Perl Artistic License Version 2.0.
// SPDX-FileCopyrightText: 2001-2026 Wilson Snyder
// SPDX-License-Identifier: LGPL-3.0-only OR Artistic-2.0
//
//=========================================================================
///
/// \file
/// \brief Verilated randomization implementation code
///
/// This file must be compiled and linked against all Verilated objects
/// that use randomization features.
///
/// See the internals documentation docs/internals.rst for details.
///
//=========================================================================

#include "verilated_random.h"

#include <cassert>
#include <cctype>
#include <cstring>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <sstream>
#include <streambuf>
#include <tuple>
#include <unordered_map>

// Diversity: tie each variable, array element, or part of one, to a random target via
//   a boolean assumption literal, then force them with (check-sat-assuming). If
//   UNSAT, (get-unsat-assumptions) names the literals clashing with the feasible
//   hard+soft base; drop one per round and recheck until SAT. Only these private
//   literals are assumed (never user constraints), and assumptions are ephemeral,
//   so hard/soft/randc semantics are untouched and rounds need no push/pop or
//   re-asserting. See solveDiversity.
#define _VL_SOLVER_HASH_LEN 1
static constexpr int diversityMaxChecks = 512;  // Most solver checks to spread one solution
static constexpr int diversityMaxSatisfied = 64;  // Most of them satisfied
// Most terms one solution's spreading ties: each check costs the solver time and memory in the
// terms it ties, which over a large array is many times the solve itself. Past it, a random
// sample of the terms is spread, and the others keep the solution's values.
static constexpr size_t diversityMaxTerms = 4096;
static constexpr int diversityWideBits = 64;  // Parts wider than this may stay unsplit
static constexpr int diversitySlotConflicts = 4;  // Elements conflicting to drop a part of all
static constexpr int diversitySlotSamples = 4;  // Elements checked for a part dropped for all
static constexpr int diversitySlotShare = 2;  // Of checks left, 1/this for a part one by one
static constexpr int diversitySlotFew = 128;  // Of its elements, 1/this conflicting one by one
static constexpr int diversityCoreFew = 4;  // Terms of an unsat core picked from as it is
// Elements past which a model's array is read whole, one value, rather than by element
static constexpr int modelWholeRead = 64;
// Terms of a solve-before layer, before the last, past which it is not spread (see
// solvePhaseValues)
static constexpr int diversityLayerTerms = 8;
// Resource limit of each spreading check, in the solver's own units (SMT-LIB 2.6
// :reproducible-resource-limit): diversityCheckLimit, plus diversityCheckLimitSquare times
// n^2, n the number of terms spread (variables and array elements, not bits). It bounds
// work, not time. For z3 the base is 1.9 times the costliest spreading check of the
// randomize tests (2.65M; 5.4M for any check), and a hard check reaches it in one to
// several seconds, depending on the check. Legitimate checks over n elements take up to
// about 5 n^2: 0.5 to 0.6 n^2 spreading n = 4000 to 12000 elements, 5 n^2 refuting every
// element for a random index into n = 1000 to 2000 of them. cvc5's units cost about 3000
// times as much, so there it is effectively no limit.
static constexpr uint64_t diversityCheckLimit = 5000000;
static constexpr uint64_t diversityCheckLimitSquare = 10;
// The largest limit z3 takes, an unsigned 32-bit option value. From about 20000 terms on,
// the limit is this one, effectively none, as before there were limits.
static constexpr uint64_t diversityCheckLimitMax = 0xffffffffULL;
// Random hashes a solution found again in a fresh session satisfies (see resolveFresh),
// in a check limited to diversityFreshLimit times the spreading checks' limit
static constexpr int diversityFreshHashes = 8;
static constexpr uint64_t diversityFreshLimit = 4;

// Index of the i-th of the elements checked out of n, spread over them
static size_t diversitySample(size_t i, size_t n) {
    const size_t nsamples = std::min<size_t>(diversitySlotSamples, n);
    return (2 * i + 1) * n / (2 * nsamples);
}

// clang-format off
#if defined(__unix__) || defined(__unix) || (defined(__APPLE__) && defined(__MACH__))
# define _VL_SOLVER_PIPE_UNIX  // Allow pipe SMT solving.  Needs fork()
#elif defined(_WIN32) || defined(__MINGW32__)
# define _VL_SOLVER_PIPE_WIN  // Allow pipe SMT solving.  Uses CreateProcess
#endif

#ifdef _VL_SOLVER_PIPE_UNIX
# include <sys/wait.h>
# include <sys/socket.h>
# include <cerrno>
# include <csignal>
# include <fcntl.h>
#endif

#ifdef _VL_SOLVER_PIPE_WIN
// <windows.h> comes from verilatedos.h, with WIN32_LEAN_AND_MEAN and NOMINMAX
# include <fcntl.h>  // _O_BINARY, _O_WRONLY, _O_RDONLY
# include <io.h>  // _open_osfhandle, read, write, close
# include <cstdlib>
# include <cstring>
#endif
// clang-format on

#ifdef _VL_SOLVER_PIPE_WIN
// Quote one argument of a command line, following the MSVCRT parsing rules:
// a backslash is special only before a quote, so double every run of
// backslashes preceding a quote; quote the whole argument if it is empty or
// contains whitespace
static std::string winQuoteArg(const char* const arg) {
    if (VL_UNLIKELY(!*arg)) return "\"\""s;
    if (!strpbrk(arg, " \t\"")) return std::string{arg};
    std::string quoted = "\"";
    unsigned backslashes = 0;
    for (const char* p = arg; *p; ++p) {
        if (*p == '\\') {
            ++backslashes;
        } else if (*p == '"') {
            quoted.append(2 * backslashes + 1, '\\');
            quoted += '"';
            backslashes = 0;
        } else {
            quoted.append(backslashes, '\\');
            quoted += *p;
            backslashes = 0;
        }
    }
    quoted.append(2 * backslashes, '\\');  // Before our closing quote
    quoted += '"';
    return quoted;
}
#endif

class VlRProcess final : private std::streambuf, public std::iostream {
    static constexpr int BUFFER_SIZE = 4096;
    const char* const* m_cmd = nullptr;  // fork() process argv
#ifdef _VL_SOLVER_PIPE_UNIX
    pid_t m_pid = 0;  // fork() process id
#elif defined(_VL_SOLVER_PIPE_WIN)
    HANDLE m_pid = nullptr;  // Child process handle
#else
    int m_pid = 0;  // fork() process id - always zero as disabled
#endif
    bool m_pidExited = true;  // If subprocess has exited and can be opened
    int m_pidStatus = 0;  // fork() process exit status, valid if m_pidExited
    int m_writeFd = -1;  // File descriptor TO subprocess
    int m_readFd = -1;  // File descriptor FROM subprocess
    char m_readBuf[BUFFER_SIZE];
    char m_writeBuf[BUFFER_SIZE];

    bool m_logTried = false;  // Log file name looked up, at the first start
    std::unique_ptr<std::ofstream> m_logfp;  // Log file stream
    uint64_t m_logLastTime = ~0ULL;  // Last timestamp for logfile
    std::string m_logLinePrefix;  // Prefix of the last logged line
    bool m_logLineOpen = false;  // Last logged line has no newline yet

public:
    typedef std::streambuf::traits_type traits_type;

protected:
    int overflow(int c = traits_type::eof()) override {
        const char c2 = static_cast<char>(c);
        if (pbase() == pptr()) return 0;
        const size_t size = pptr() - pbase();
        log("  ", std::string(pbase(), size));
        // write() may write only part of the buffer
        for (size_t done = 0; done < size;) {
#if defined(_VL_SOLVER_PIPE_UNIX) && defined(MSG_NOSIGNAL)
            const ssize_t n = ::send(m_writeFd, pbase() + done, size - done, MSG_NOSIGNAL);
#elif defined(_VL_SOLVER_PIPE_UNIX) && defined(SO_NOSIGPIPE)
            const ssize_t n = ::send(m_writeFd, pbase() + done, size - done, 0);
#elif defined(_VL_SOLVER_PIPE_UNIX)
            errno = ENOTSUP;
            const ssize_t n = -1;
#else
            const ssize_t n = ::write(m_writeFd, pbase() + done, size - done);
#endif
            if (VL_UNLIKELY(n == -1)) perror("write");
            if (n <= 0) {
                wait_report();
                return traits_type::eof();
            }
            done += n;
        }
        setp(m_writeBuf, m_writeBuf + sizeof(m_writeBuf));
        if (c != traits_type::eof()) sputc(c2);
        return 0;
    }
    int underflow() override {
        sync();
        const ssize_t n = ::read(m_readFd, m_readBuf, sizeof(m_readBuf));
        if (VL_UNLIKELY(n == -1)) perror("read");
        if (n <= 0) {
            wait_report();
            return traits_type::eof();
        }
        log("< ", std::string(m_readBuf, n));
        setg(m_readBuf, m_readBuf, m_readBuf + n);
        return traits_type::to_int_type(m_readBuf[0]);
    }
    int sync() override {
        overflow();
        return 0;
    }

public:
    explicit VlRProcess(const char* const* const cmd = nullptr)
        : std::streambuf{}
        , std::iostream{this}
        , m_cmd{cmd} {
        open(cmd);
    }

    // Kill and reap a solver that is still running, so no child is left behind
    void terminate() {
        if (!m_pidExited && m_pid) {
#ifdef _VL_SOLVER_PIPE_UNIX
            ::kill(m_pid, SIGKILL);
            waitpid(m_pid, &m_pidStatus, 0);
#elif defined(_VL_SOLVER_PIPE_WIN)
            TerminateProcess(m_pid, EXIT_FAILURE);
            WaitForSingleObject(m_pid, INFINITE);
            CloseHandle(m_pid);
#endif
        }
        m_pidExited = true;
        m_pid = 0;  // Reaped pid, or null HANDLE
        closeFds();
    }

    // Report the subprocess' nonzero exit status or signal, if any
    void reportFailure(const std::string& reason) const {
        std::stringstream msg;
        msg << "Subprocess command `" << m_cmd[0];
        for (const char* const* arg = m_cmd + 1; *arg; ++arg) msg << ' ' << *arg;
        msg << "' failed: " << reason;
        const std::string str = msg.str();
        VL_WARN_MT("", 0, "VlRProcess", str.c_str());
    }

    void wait_report() {
        if (m_pidExited) return;
        bool reaped = true;
#ifdef _VL_SOLVER_PIPE_UNIX
        const pid_t rc = waitpid(m_pid, &m_pidStatus, WNOHANG);
        if (rc != m_pid) m_pidStatus = 0;
        reaped = rc != 0;  // Zero means still running, so terminate() reaps it
        if (m_pidStatus) {
            std::string reason;
            if (WIFSIGNALED(m_pidStatus)) {
                reason = strsignal(WTERMSIG(m_pidStatus));
                if (WCOREDUMP(m_pidStatus)) reason += " (core dumped)";
            } else if (WIFEXITED(m_pidStatus)) {
                reason = "exit status "s + std::to_string(WEXITSTATUS(m_pidStatus));
            }
            reportFailure(reason);
        }
#elif defined(_VL_SOLVER_PIPE_WIN)
        if (m_pid) {
            if (WaitForSingleObject(m_pid, 0) == WAIT_OBJECT_0) {
                DWORD exitCode = 0;
                GetExitCodeProcess(m_pid, &exitCode);
                m_pidStatus = static_cast<int>(exitCode);
                if (m_pidStatus) reportFailure("exit status "s + std::to_string(m_pidStatus));
                CloseHandle(m_pid);
                m_pid = 0;
            } else {
                reaped = false;  // Still running, so terminate() reaps it
            }
        }
#endif
        if (reaped) {
            m_pidExited = true;
            m_pid = 0;
        }
        closeFds();
    }

    void closeFds() {
        if (m_writeFd != -1) {
            close(m_writeFd);
            m_writeFd = -1;
        }
        if (m_readFd != -1) {
            close(m_readFd);
            m_readFd = -1;
        }
    }

    bool open(const char* const* const cmd) {
        clear();
        setp(std::begin(m_writeBuf), std::end(m_writeBuf));
        setg(m_readBuf, m_readBuf, m_readBuf);
        if (VL_UNLIKELY(!cmd || !cmd[0])) return false;
        m_cmd = cmd;
        if (!m_logTried) {
            m_logTried = true;
            logOpen();
        }
        log("", "# Open: "s + cmd[0]);
#ifdef _VL_SOLVER_PIPE_UNIX
#if !defined(MSG_NOSIGNAL) && !defined(SO_NOSIGPIPE)
        errno = ENOTSUP;
        perror("VlRProcess::open: SIGPIPE suppression");
        return false;
#endif
        int fd_stdin[2];  // Can't use std::array
        int fd_stdout[2];  // Can't use std::array
        constexpr int P_RD = 0;
        constexpr int P_WR = 1;

        // Suppress SIGPIPE on the request endpoint without changing program signal state.
        if (VL_UNLIKELY(socketpair(AF_UNIX, SOCK_STREAM, 0, fd_stdin) != 0)) {
            perror("VlRProcess::open: socketpair");
            return false;
        }
#if !defined(MSG_NOSIGNAL) && defined(SO_NOSIGPIPE)
        const int noSigpipe = 1;
        if (VL_UNLIKELY(
                setsockopt(fd_stdin[P_WR], SOL_SOCKET, SO_NOSIGPIPE, &noSigpipe, sizeof(noSigpipe))
                != 0)) {
            perror("VlRProcess::open: SO_NOSIGPIPE");
            close(fd_stdin[P_RD]);
            close(fd_stdin[P_WR]);
            return false;
        }
#endif
        if (VL_UNLIKELY(pipe(fd_stdout) != 0)) {
            perror("VlRProcess::open: pipe");
            close(fd_stdin[P_RD]);
            close(fd_stdin[P_WR]);
            return false;
        }

        if (fd_stdin[P_RD] <= 2 || fd_stdin[P_WR] <= 2 || fd_stdout[P_RD] <= 2
            || fd_stdout[P_WR] <= 2) {
            // We'd have to rearrange all of the FD usages in this case.
            // Too unlikely; verilator isn't a daemon.
            fprintf(stderr, "stdin/stdout closed before pipe opened\n");
            close(fd_stdin[P_RD]);
            close(fd_stdin[P_WR]);
            close(fd_stdout[P_RD]);
            close(fd_stdout[P_WR]);
            return false;
        }

        const pid_t pid = fork();
        if (VL_UNLIKELY(pid < 0)) {
            perror("VlRProcess::open: fork");
            close(fd_stdin[P_RD]);
            close(fd_stdin[P_WR]);
            close(fd_stdout[P_RD]);
            close(fd_stdout[P_WR]);
            return false;
        }
        if (pid == 0) {
            // Child
            close(fd_stdin[P_WR]);
            dup2(fd_stdin[P_RD], STDIN_FILENO);
            close(fd_stdin[P_RD]);
            close(fd_stdout[P_RD]);
            dup2(fd_stdout[P_WR], STDOUT_FILENO);
            close(fd_stdout[P_WR]);
            execvp(cmd[0], const_cast<char* const*>(cmd));
            std::stringstream msg;
            msg << "VlRProcess::open: execvp(" << cmd[0] << ")";
            const std::string str = msg.str();
            perror(str.c_str());
            _exit(127);
        }
        // Parent
        m_pid = pid;
        m_pidExited = false;
        m_pidStatus = 0;
        m_readFd = fd_stdout[P_RD];
        m_writeFd = fd_stdin[P_WR];

        close(fd_stdin[P_RD]);
        close(fd_stdout[P_WR]);

        return true;
#elif defined(_VL_SOLVER_PIPE_WIN)
        SECURITY_ATTRIBUTES sa;
        sa.nLength = sizeof(SECURITY_ATTRIBUTES);
        sa.lpSecurityDescriptor = nullptr;
        sa.bInheritHandle = TRUE;  // The child must inherit the pipe ends
        HANDLE fd_stdin_rd = nullptr;  // Pipe end the child reads (we write)
        HANDLE fd_stdin_wr = nullptr;
        HANDLE fd_stdout_rd = nullptr;  // Pipe end the child writes (we read)
        HANDLE fd_stdout_wr = nullptr;
        if (VL_UNLIKELY(!CreatePipe(&fd_stdin_rd, &fd_stdin_wr, &sa, 0))) {
            fprintf(stderr, "VlRProcess::open: CreatePipe failed\n");
            return false;
        }
        if (VL_UNLIKELY(!CreatePipe(&fd_stdout_rd, &fd_stdout_wr, &sa, 0))) {
            fprintf(stderr, "VlRProcess::open: CreatePipe failed\n");
            CloseHandle(fd_stdin_rd);
            CloseHandle(fd_stdin_wr);
            return false;
        }
        // The parent's pipe ends must not be inherited, else the child holds
        // copies of them and the pipes never reach EOF after we close our side
        SetHandleInformation(fd_stdin_wr, HANDLE_FLAG_INHERIT, 0);
        SetHandleInformation(fd_stdout_rd, HANDLE_FLAG_INHERIT, 0);

        // Pass the parent's stderr through to the child, like the Unix version
        HANDLE stderrOrig = GetStdHandle(STD_ERROR_HANDLE);
        HANDLE stderrInheritable = nullptr;
        if (stderrOrig && (stderrOrig != INVALID_HANDLE_VALUE)) {
            DuplicateHandle(GetCurrentProcess(), stderrOrig, GetCurrentProcess(),
                            &stderrInheritable, 0, TRUE /* inheritable */, DUPLICATE_SAME_ACCESS);
        }

        // Build the command line string, quoting each argument
        std::string cmdline;
        for (const char* const* arg = cmd; *arg; ++arg) {
            if (arg != cmd) cmdline += ' ';
            cmdline += winQuoteArg(*arg);
        }

        STARTUPINFOA si;
        ZeroMemory(&si, sizeof(si));
        si.cb = sizeof(si);
        si.dwFlags = STARTF_USESTDHANDLES;
        si.hStdInput = fd_stdin_rd;
        si.hStdOutput = fd_stdout_wr;
        si.hStdError = stderrInheritable ? stderrInheritable : fd_stdout_wr;
        PROCESS_INFORMATION pi;
        ZeroMemory(&pi, sizeof(pi));
        const BOOL procOk
            = CreateProcessA(nullptr, &cmdline[0], nullptr, nullptr, TRUE /* inherit */,
                             CREATE_NO_WINDOW, nullptr, nullptr, &si, &pi);
        // The child's ends are consumed by the child; close our references
        CloseHandle(fd_stdin_rd);
        CloseHandle(fd_stdout_wr);
        if (stderrInheritable) CloseHandle(stderrInheritable);
        if (VL_UNLIKELY(!procOk)) {
            std::stringstream msg;
            msg << "VlRProcess::open: CreateProcess(" << cmd[0] << ") error " << GetLastError();
            const std::string str = msg.str();
            fprintf(stderr, "%s\n", str.c_str());
            CloseHandle(fd_stdin_wr);
            CloseHandle(fd_stdout_rd);
            return false;
        }
        CloseHandle(pi.hThread);  // Only the process handle is of interest
        m_pid = pi.hProcess;
        m_pidExited = false;
        m_pidStatus = 0;
        // Hand the pipe ends to the C runtime as file descriptors, so the
        // streambuf overflow/underflow read/write code is platform independent
        m_writeFd
            = _open_osfhandle(reinterpret_cast<intptr_t>(fd_stdin_wr), _O_WRONLY | _O_BINARY);
        m_readFd
            = _open_osfhandle(reinterpret_cast<intptr_t>(fd_stdout_rd), _O_RDONLY | _O_BINARY);
        if (VL_UNLIKELY(m_writeFd == -1 || m_readFd == -1)) {
            // A handle taken by _open_osfhandle is owned by its descriptor and
            // closed by closeFds; close only the one the CRT did not take
            if (m_writeFd == -1) CloseHandle(fd_stdin_wr);
            if (m_readFd == -1) CloseHandle(fd_stdout_rd);
            terminate();
            return false;
        }
        return true;
#else
        return false;
#endif
    }

private:
    void logOpen() {
        const std::string filename = Verilated::threadContextp()->solverLogFilename();
        if (filename.empty()) return;
        m_logfp = std::make_unique<std::ofstream>(filename);
        if (m_logfp.get() && m_logfp.get()->fail()) m_logfp = nullptr;
        if (!m_logfp) {
            const std::string msg = "%Error: Can't write '"s + filename + "'";
            VL_FATAL_MT("", 0, "", msg.c_str());
            return;
        }
        *m_logfp << "# Verilator solver log\n";
    }
    // Commands and replies are logged one I/O buffer at a time, and a buffer may end within
    // a line, so a logged line ends only at its own newline, or where text with a different
    // prefix follows
    void log(const std::string& prefix, const std::string& text) {
        if (VL_LIKELY(!m_logfp.get()) || text.empty()) return;
        if (m_logLineOpen && prefix != m_logLinePrefix) {
            *m_logfp << '\n';
            m_logLineOpen = false;
        }
        m_logLinePrefix = prefix;
        for (const char c : text) {
            if (!m_logLineOpen) {
                if (m_logLastTime != Verilated::threadContextp()->time()) {
                    m_logLastTime = Verilated::threadContextp()->time();
                    *m_logfp << "# [" << Verilated::threadContextp()->timeWithUnitString()
                             << "]\n";
                }
                *m_logfp << prefix;
            }
            m_logfp->put(c);
            m_logLineOpen = c != '\n';
        }
    }
};

//======================================================================
// Solver reply protocol

enum class VlSolverStatus : uint8_t { SAT, UNSAT, UNKNOWN, FAIL };

static bool isSolverError(const std::string& reply) { return reply.compare(0, 6, "(error") == 0; }

// One non-blank reply line, trimmed; false once the solver stops answering
static bool readLine(std::istream& is, std::string& liner) {
    while (std::getline(is, liner)) {
        const size_t first = liner.find_first_not_of(" \t\r");
        if (first == std::string::npos) continue;
        const size_t last = liner.find_last_not_of(" \t\r");
        liner = liner.substr(first, last - first + 1);
        return true;
    }
    return false;
}

static bool scanParenDepth(const std::string& str, int& depthr, bool& inStringr) {
    for (const char c : str) {
        if (inStringr) {
            if (c == '"') inStringr = false;
        } else if (c == '"') {
            inStringr = true;
        } else if (c == '(') {
            ++depthr;
        } else if (c == ')') {
            if (depthr == 0) return false;
            --depthr;
        }
    }
    return true;
}

// Append lines until the error s-expression started in liner is paren-balanced
static void finishErrorReply(std::istream& is, std::string& liner) {
    int depth = 0;
    bool inString = false;
    if (!scanParenDepth(liner, depth, inString)) return;
    while (depth > 0) {
        std::string chunk;
        if (!readLine(is, chunk)) return;
        liner += ' ';
        liner += chunk;
        if (!scanParenDepth(chunk, depth, inString)) return;
    }
}

void VlRandomizer::fail_pending(const std::string& msg, const char* filename, uint32_t linenum,
                                bool warned) {
    if (failed()) return;
    m_failPending = msg;
    m_failFilename = filename;
    m_failLinenum = linenum;
    m_failWarned = warned;
}

bool VlRandomizer::array_size_ok(IData size, const char* name, const char* filename,
                                 uint32_t linenum) {
    // Unsigned, as a solved size of 2**31 or more is not a small negative one
    const IData maxSize = static_cast<IData>(Verilated::threadContextp()->randArrayMax());
    if (VL_LIKELY(size <= maxSize)) return true;
    const std::string msg = "randomize() returns 0: the constraints give '" + std::string{name}
                            + "' " + std::to_string(size) + " elements, over the "
                            + std::to_string(maxSize)
                            + " of +verilator+rand+array+max+<n>; constrain its size, or raise"
                              " the limit.";
    VL_WARN_MT(filename, linenum, "", msg.c_str());
    fail_pending(msg, filename, linenum, true);
    return false;
}

static void warnSolverReply(const std::string& reply) {
    static bool s_warned = false;
    if (s_warned) return;
    s_warned = true;
    const std::string msg
        = "Solver did not answer with a status, so randomize() returns 0; warned once: " + reply;
    VL_WARN_MT(__FILE__, __LINE__, "randomize", msg.c_str());
}

// Whether a status is unknown with a reason, an upper-case word in parentheses
static bool isUnknownReason(const std::string& line) {
    static const std::string prefix = "unknown (";
    if (line.size() <= prefix.size() + 1 || line.compare(0, prefix.size(), prefix) != 0
        || line.back() != ')') {
        return false;
    }
    for (size_t i = prefix.size(); i + 1 < line.size(); ++i) {
        if (!std::isupper(static_cast<unsigned char>(line[i])) && line[i] != '_') return false;
    }
    return true;
}

// Read one solver status; only a print-success echo may precede it. A check under a
// resource limit may stop short, so its unknown is not warned. A reply that is not a
// status is returned in replyr, for the caller to warn of.
static VlSolverStatus readStatus(std::istream& is, bool limited, std::string& replyr) {
    std::string line;
    while (readLine(is, line)) {
        if (line == "success") continue;
        if (line == "sat") return VlSolverStatus::SAT;
        if (line == "unsat") return VlSolverStatus::UNSAT;
        // cvc5 gives its reason too: unknown (RESOURCEOUT), under a resource limit
        if (line == "unknown" || isUnknownReason(line)) {
            static bool s_warnedUnknown = false;
            if (!limited && !s_warnedUnknown) {
                s_warnedUnknown = true;
                VL_WARN_MT(__FILE__, __LINE__, "randomize",
                           "Solver returned unknown (timed out or incomplete), so randomize() "
                           "may return 0; warned once");
            }
            return VlSolverStatus::UNKNOWN;
        }
        // Consume the whole error, so the next read starts on a reply boundary
        if (isSolverError(line)) finishErrorReply(is, line);
        replyr = line;
        return VlSolverStatus::FAIL;
    }
    return VlSolverStatus::FAIL;
}

// Read one complete paren-balanced s-expression, which may span lines
static bool readSExpr(std::istream& is, std::string& outr) {
    outr.clear();
    std::string pre;
    int depth = 0;
    bool inString = false;
    char c = 0;
    while (is.get(c)) {
        if (depth == 0) {
            if (c == '(') {
                if (!pre.empty()) break;
                outr += c;
                depth = 1;
            } else if (c == '\n') {
                if (pre == "success") pre.clear();
                if (!pre.empty()) break;
            } else if (c != ' ' && c != '\t' && c != '\r') {
                pre += c;
            }
            continue;
        }
        outr += c;
        if (inString) {
            if (c == '"') inString = false;
        } else if (c == '"') {
            inString = true;
        } else if (c == '(') {
            ++depth;
        } else if (c == ')') {
            assert(depth > 0);
            if (--depth == 0) return true;
        }
    }
    return false;
}

//======================================================================
// Solver session lifecycle

// With +verilator+rand+sampler+solver the solver's model is the random result, so
// Verilator's own sampling (UniGen2 cells and diversity pins) is skipped.
static bool solverSamples() {
    return Verilated::threadContextp()->randSampler() == VerilatedRandSampler::SAMPLER_SOLVER;
}

// Owns the solver process; serializes transactions and replaces a solver that
// died or was left out of step with the reply stream
class VlSolverSession final {
    friend class VlRandomizer;
    friend class VlSolverTxn;
    friend class VlSolverLimit;
    enum class State : uint8_t { UNSTARTED, LIVE, BROKEN, DISABLED };
    static constexpr int MAX_CONSEC_FAILS = 3;

    VerilatedMutex m_mutex;  // Serializes whole solver transactions
    VlRProcess m_proc VL_GUARDED_BY(m_mutex);  // Solver subprocess and its pipes
    State m_state VL_GUARDED_BY(m_mutex) = State::UNSTARTED;
    int m_consecFails VL_GUARDED_BY(m_mutex) = 0;  // Failed transactions in a row
    bool m_dirty VL_GUARDED_BY(m_mutex) = false;  // Transaction left the pipe out of step
    bool m_stale VL_GUARDED_BY(m_mutex) = false;  // Replies of later commands may be queued
    std::string m_program VL_GUARDED_BY(m_mutex);  // Storage backing m_argv
    std::vector<const char*> m_argv VL_GUARDED_BY(m_mutex);  // Solver argv
    bool m_warnedRestart VL_GUARDED_BY(m_mutex) = false;
    bool m_takesLimit VL_GUARDED_BY(m_mutex) = false;  // Takes :reproducible-resource-limit
    bool m_limited VL_GUARDED_BY(m_mutex) = false;  // Checks are under a resource limit
    bool m_broke VL_GUARDED_BY(m_mutex) = false;  // A transaction of this call broke the solver
    bool m_holdReplies VL_GUARDED_BY(m_mutex) = false;  // Hold reply warnings (warnReply)
    std::string m_heldReply VL_GUARDED_BY(m_mutex);  // First reply warning held

public:
    std::iostream& os() VL_REQUIRES(m_mutex) { return m_proc; }
    // The pipe may hold bytes of an abandoned reply, so replace the solver
    void abandon() VL_REQUIRES(m_mutex) { m_dirty = true; }
    // A reply failed, was abandoned or never came, in this transaction
    bool failed() const VL_REQUIRES(m_mutex) { return m_stale || m_dirty || m_proc.fail(); }
    // Start a randomize() call
    void beginCall() VL_REQUIRES(m_mutex) { m_broke = false; }
    // End a randomize() call. One returning 1 has its solution, so is not a failed one even if
    // the solver broke after finding it; one returning 0 because the solver broke says so.
    void endCall(bool result) VL_REQUIRES(m_mutex) {
        if (result) {
            m_consecFails = 0;
        } else if (m_broke && !m_warnedRestart) {
            m_warnedRestart = true;
            VL_WARN_MT(__FILE__, __LINE__, "randomize",
                       "Solver died or replied unreadably, so this randomize() returned 0; "
                       "restarting it, warned once");
        }
    }
    // Warn of a reply that is not the one asked for. While a solution is spread the warning
    // is held, for nextRandomize() to give if the call returns 0: a call that keeps its
    // solution returns 1, and warns that the spreading failed instead.
    void warnReply(const std::string& reply) VL_REQUIRES(m_mutex) {
        if (!m_holdReplies) {
            warnSolverReply(reply);
        } else if (m_heldReply.empty()) {
            m_heldReply = reply;
        }
    }
    void holdReplies(bool hold) VL_REQUIRES(m_mutex) { m_holdReplies = hold; }
    // The reply warning held, which is then cleared
    std::string takeHeldReply() VL_REQUIRES(m_mutex) {
        std::string reply;
        reply.swap(m_heldReply);
        return reply;
    }

    // Read a check-sat status; once one fails, so does every later read until resync()
    VlSolverStatus readStatus() VL_REQUIRES(m_mutex) {
        // The failed read may have taken an error answering an earlier command of the batch
        // (SMT-LIB 2.6 section 4.1.2), so later replies cannot be matched to their commands
        if (m_stale) return VlSolverStatus::FAIL;
        std::string reply;  // A reply that is not a status
        const VlSolverStatus status = ::readStatus(m_proc, m_limited, reply);
        if (!reply.empty()) warnReply(reply);
        m_stale = status == VlSolverStatus::FAIL;
        return status;
    }
    // An unreadable reply means text of it may still be queued, so it is not
    // safe to read anything more from this solver
    bool readSExpr(std::string& outr) VL_REQUIRES(m_mutex) {
        if (::readSExpr(m_proc, outr)) return true;
        abandon();
        return false;
    }
    // Limit the effort of each later check, or lift the limit with 0; a solver that does
    // not take the option checks without one
    void limitChecks(uint64_t limit) VL_REQUIRES(m_mutex) {
        if (!m_takesLimit || (!limit && !m_limited)) return;
        m_proc << "(set-option :reproducible-resource-limit " << limit << ")\n";
        m_limited = limit != 0;
    }

    // Start a transaction, spawning or respawning the solver as needed
    bool begin() VL_REQUIRES(m_mutex) {
        m_dirty = false;
        if (m_state == State::BROKEN && m_consecFails >= MAX_CONSEC_FAILS) {
            m_state = State::DISABLED;
            VL_WARN_MT(__FILE__, __LINE__, "randomize",
                       "Solver failed repeatedly, so randomize() returns 0 from now on");
        }
        if (m_state == State::UNSTARTED || m_state == State::BROKEN) spawn();
        return m_state == State::LIVE;
    }

    // End a transaction; a solver left out of step or dead is replaced next time
    void end() VL_REQUIRES(m_mutex) {
        if (m_stale && !m_dirty) resync();
        bool healthy = !m_dirty && !m_proc.fail();
        if (healthy) {
            m_proc << "(reset)\n";
            m_proc.flush();
            healthy = !m_proc.fail();
        }
        if (healthy) {
            m_consecFails = 0;
        } else {
            m_proc.terminate();
            m_state = State::BROKEN;
            m_broke = true;
            ++m_consecFails;
        }
        m_dirty = false;
        m_stale = false;
    }

private:
    // Skip queued replies up to an echoed marker, and tell whether all were print-success
    // echoes; a solver that went away stays out of step
    bool resync() VL_REQUIRES(m_mutex) {
        m_proc << "(echo \"vl_resync\")\n";
        std::string line;
        bool quiet = true;
        // SMT-LIB 2.6 section 4.2.9 echoes the string with its quotes, z3 without them
        while (readLine(m_proc, line) && line != "vl_resync" && line != "\"vl_resync\"") {
            quiet &= line == "success";
            // A queued error is read whole, as its text may hold a line like the marker
            if (isSolverError(line)) finishErrorReply(m_proc, line);
        }
        if (!m_proc.fail()) m_stale = false;
        return quiet && !m_proc.fail();
    }

    // A solver that will not start is not started again
    void spawn() VL_REQUIRES(m_mutex) {
        if (m_argv.empty()) {
            m_program = Verilated::threadContextp()->solverProgram();
            m_argv.emplace_back(&m_program[0]);
            for (char* argp = &m_program[0]; *argp; ++argp) {
                if (*argp == ' ') {
                    *argp = '\0';
                    m_argv.emplace_back(argp + 1);
                }
            }
            m_argv.emplace_back(nullptr);
        }
        m_proc.open(m_argv.data());
        // Names the sampler in the +verilator+solver+file log
        m_proc << "; sampler: " << (solverSamples() ? "solver" : "default") << "\n";
        m_proc << "(set-logic QF_ABV)\n";
        m_proc << "(check-sat)\n";
        // A solver without the option answers it with 'unsupported' or an error
        m_proc << "(set-option :reproducible-resource-limit 0)\n";
        m_proc << "(reset)\n";
        if (readStatus() == VlSolverStatus::SAT) {
            m_takesLimit = resync();
            m_state = State::LIVE;
            m_dirty = false;
            return;
        }
        m_proc.terminate();
        m_state = State::DISABLED;
        std::stringstream msg;
        msg << "Unable to communicate with SAT solver, please check its installation or specify a "
               "different one in VERILATOR_SOLVER environment variable.\n";
        msg << " ... Tried: $";
        for (const char* const* argp = m_argv.data(); *argp; ++argp) msg << ' ' << *argp;
        msg << '\n';
        const std::string str = msg.str();
        VL_WARN_MT("", 0, "randomize", str.c_str());
    }
};

// Constructed before main(), so nothing here may touch the thread context
static VlSolverSession s_solverSession;

// One solver transaction; the caller holds the session mutex
class VlSolverTxn final {
    VlSolverSession& m_sess;
    const bool m_ok;  // Session transaction began successfully

public:
    explicit VlSolverTxn(VlSolverSession& sess) VL_REQUIRES(sess.m_mutex)
        : m_sess{sess}
        , m_ok{sess.begin()} {}
    // Analysis cannot see through the reference member back to the caller's lock
    ~VlSolverTxn() VL_NO_THREAD_SAFETY_ANALYSIS {
        if (m_ok) m_sess.end();
    }
    bool ok() const { return m_ok; }
};

// Limits each solver check while it lives: a spreading check cut short keeps the solution
// found, but a main check must never be, so the limit is lifted on every exit
class VlSolverLimit final {
    VlSolverSession& m_sess;

public:
    VlSolverLimit(VlSolverSession& sess, uint64_t limit) VL_REQUIRES(sess.m_mutex)
        : m_sess{sess} {
        sess.limitChecks(limit);
    }
    // Analysis cannot see through the reference member back to the caller's lock
    ~VlSolverLimit() VL_NO_THREAD_SAFETY_ANALYSIS { m_sess.limitChecks(0); }
};

// One SMT-LIB term from a solver reply: a symbol or literal, or a parenthesized term
// through its balancing ')'. Stops before a ')' that closes an enclosing term.
static std::string readSMTTerm(std::istream& is) {
    std::string term;
    int depth = 0;
    char c = 0;
    is >> std::ws;
    while (is.get(c)) {
        if (depth == 0 && (c == ')' || std::isspace(static_cast<unsigned char>(c)))) {
            is.unget();
            break;
        }
        term += c;
        if (c == '(') {
            ++depth;
        } else if (c == ')' && --depth == 0) {
            break;
        }
    }
    return term;
}

// The last term of an S-expression, consuming its closing ')'. Anything else before the ')'
// is kept in the result, so that it is no longer a valid term.
static std::string readSMTLastTerm(std::istream& is) {
    const std::string term = readSMTTerm(is);
    std::string rest;
    std::getline(is >> std::ws, rest, ')');
    return rest.empty() ? term : term + ' ' + rest;
}

// Array name of a (possibly nested) (select <array> <index>) term, appending its
// index terms in declaration order, the leftmost first; any other term is returned as is.
static std::string parseSelect(const std::string& term, std::vector<std::string>& indices) {
    std::istringstream is{term};
    std::string op;
    is >> op;
    if (op != "(select") return term;
    const std::string name = parseSelect(readSMTTerm(is), indices);
    indices.push_back(readSMTLastTerm(is));
    return name;
}

//======================================================================
// VlRandomizer:: Methods

void VlRandomVar::emitGetValue(std::ostream& s) const { s << ' ' << m_name; }
void VlRandomVar::emitExtract(std::ostream& s, int i) const {
    s << " ((_ extract " << i << ' ' << i << ") " << m_name << ')';
}
void VlRandomVar::emitType(std::ostream& s) const { s << "(_ BitVec " << width() << ')'; }
// A scalar var IS its only element, so "element j" is just the whole var.
void VlRandomVar::emitElement(std::ostream& s, int /*j*/) const { s << ' ' << m_name; }
// Serialize the current runtime value as an SMT-LIB binary literal. Used by
// randomize(null) to pin a var via `(assert (= var #b...))`. Binary (#b)
// rather than hex (#x) sidesteps SMT-LIB's hex-width-multiple-of-4 rule.
void VlRandomVar::emitConcreteValue(std::ostream& s, int j) const {
    const int w = width();
    const void* const dp = datap(j);
    s << "#b";
    for (int i = w - 1; i >= 0; --i) {
        int bit = 0;
        if (w <= VL_BYTESIZE) {
            bit = (*static_cast<const CData*>(dp) >> i) & 1;
        } else if (w <= VL_SHORTSIZE) {
            bit = (*static_cast<const SData*>(dp) >> i) & 1;
        } else if (w <= VL_IDATASIZE) {
            bit = (*static_cast<const IData*>(dp) >> i) & 1;
        } else if (w <= VL_QUADSIZE) {
            bit = (*static_cast<const QData*>(dp) >> i) & 1;
        } else {
            const WDataInP wp = WDataInP::external(static_cast<const EData*>(dp));
            bit = (wp[VL_BITWORD_E(i)] >> VL_BITBIT_E(i)) & 1;
        }
        s << (bit ? '1' : '0');
    }
}
int VlRandomVar::totalWidth() const { return m_width; }
// Rewrite an indexed bit-vector literal (_ bvX n), of the expected 'width', as the binary
// literal #b of the same value, so a reply may use either SMT-LIB 2.6 notation. Anything
// else, including an indexed literal of another width, is left for validSMTNum to reject.
static void smtIndexedToBinary(std::string& valr, int width) {
    if (valr.compare(0, 1, "(") != 0) return;
    // The term's tokens, single-spaced, so any whitespace between them is accepted
    std::istringstream is{valr.substr(1, valr.size() - 2)};
    std::string literal = "(";
    for (std::string token; is >> token;) literal += token + ' ';
    literal.back() = ')';
    if (literal.compare(0, 5, "(_ bv") != 0) return;
    const std::string numeral = literal.substr(5, literal.find(' ', 5) - 5);
    // A value below 2^width has at most width digits; size() - 1 also rejects no digits
    if (numeral.find_first_not_of("0123456789") != std::string::npos
        || numeral.size() - 1 >= static_cast<size_t>(width)
        || literal.compare(5 + numeral.size(), std::string::npos,
                           " " + std::to_string(width) + ")")
               != 0) {
        return;
    }
    // Decimal to binary a word at a time; SMT-LIB makes X >= 2^n an error
    std::vector<EData> words((static_cast<size_t>(width) + VL_EDATASIZE - 1) / VL_EDATASIZE, 0);
    bool overflow = false;
    for (const char digit : numeral) {
        QData carry = digit - '0';
        for (EData& word : words) {
            carry += static_cast<QData>(word) * 10;
            word = static_cast<EData>(carry);
            carry >>= VL_EDATASIZE;
        }
        overflow |= carry != 0;
    }
    overflow |= (words.back() & ~VL_MASK_E(width)) != 0;
    if (overflow) return;
    // In binary, as bsat() sends the value back to the solver, and #x spells only widths that
    // are a multiple of 4
    valr = "#b";
    for (int i = width - 1; i >= 0; --i) {
        valr += ((words[VL_BITWORD_E(i)] >> VL_BITBIT_E(i)) & 1) ? '1' : '0';
    }
}

// True if val is "#b/#o/#x/#h" followed by digits legal for that base
static bool validSMTNum(const std::string& val) {
    if (val.size() < 2 || val[0] != '#') return false;
    size_t i = 1;
    int base;
    switch (val[i++]) {
    case 'b': base = 2; break;
    case 'o': base = 8; break;
    case 'h':  // FALLTHRU
    case 'x': base = 16; break;
    default: return false;
    }
    const size_t end = val.find_last_not_of(" \t\r");
    if (end < i) return false;
    for (; i <= end; ++i) {
        const char c = val[i];
        int digit;
        if (c >= '0' && c <= '9') {
            digit = c - '0';
        } else if (c >= 'a' && c <= 'f') {
            digit = c - 'a' + 10;
        } else if (c >= 'A' && c <= 'F') {
            digit = c - 'A' + 10;
        } else {
            return false;
        }
        if (digit >= base) return false;
    }
    return true;
}

// Width in bits of val, which must have passed validSMTNum
static size_t smtNumWidth(const std::string& val) {
    const size_t digits = val.size() - 2;
    switch (val[1]) {
    case 'b': return digits;
    case 'o': return 3 * digits;
    default: return 4 * digits;
    }
}

// True if val, which must have passed validSMTNum, is a value for a variable of width bits.
// A #b or #x literal has a bit-vector sort, which must be the variable's; the octal and #h
// forms are not SMT-LIB literals and keep being read by value only.
static bool smtValueOfWidth(const std::string& val, int width) {
    return (val[1] != 'b' && val[1] != 'x') || smtNumWidth(val) == static_cast<size_t>(width);
}

// True if val is an SMT-LIB literal of width bits, after rewriting an indexed literal as binary:
// a value sent back to the solver must be one
static bool smtLiteralOfWidth(std::string& valr, size_t width) {
    smtIndexedToBinary(valr, static_cast<int>(width));
    return validSMTNum(valr) && (valr[1] == 'b' || valr[1] == 'x') && smtNumWidth(valr) == width;
}

// The tokens of an SMT-LIB term: each parenthesis, and each symbol or literal between them
static std::vector<std::string> smtTokens(const std::string& term) {
    std::vector<std::string> tokens;
    for (size_t i = 0; i < term.size();) {
        const char c = term[i];
        size_t end = i + 1;
        if (std::isspace(static_cast<unsigned char>(c))) {
            ++i;
            continue;
        } else if (c != '(' && c != ')') {
            end = term.find_first_of("() \t\r\n", i);
            if (end == std::string::npos) end = term.size();
        }
        tokens.emplace_back(term, i, end - i);
        i = end;
    }
    return tokens;
}

static const std::string& smtToken(const std::vector<std::string>& tokens, size_t i) {
    static const std::string s_end;
    return i < tokens.size() ? tokens[i] : s_end;
}

// Reads at tokens[i] a literal of width bits, plain or indexed (_ bvX n)
static bool smtReadLiteral(const std::vector<std::string>& tokens, size_t& i, size_t width) {
    std::string literal = smtToken(tokens, i++);
    if (literal == "(") {
        // (_ bvX n), whose spelling smtLiteralOfWidth checks
        if (smtToken(tokens, i + 3) != ")") return false;
        literal += smtToken(tokens, i) + ' ' + smtToken(tokens, i + 1) + ' '
                   + smtToken(tokens, i + 2) + ')';
        i += 4;
    }
    return smtLiteralOfWidth(literal, width);
}

// For each token, one past the term that starts there, found for all at once
static std::vector<size_t> smtTermEnds(const std::vector<std::string>& tokens) {
    std::vector<size_t> ends(tokens.size(), tokens.size());  // An unclosed '(' runs to the end
    std::vector<size_t> opens;
    for (size_t i = 0; i < tokens.size(); ++i) {
        if (tokens[i] == "(") {
            opens.push_back(i);
            continue;
        }
        ends[i] = i + 1;
        if (tokens[i] == ")" && !opens.empty()) {
            ends[opens.back()] = i + 1;
            opens.pop_back();
        }
    }
    return ends;
}

// True if name is an SMT-LIB simple symbol other than a reserved word
static bool smtSimpleSymbol(const std::string& name) {
    // The reserved words, then the command names, which SMT-LIB 2.6 also reserves
    static const std::unordered_set<std::string> s_reserved{"!",
                                                            "_",
                                                            "as",
                                                            "BINARY",
                                                            "DECIMAL",
                                                            "exists",
                                                            "forall",
                                                            "HEXADECIMAL",
                                                            "let",
                                                            "match",
                                                            "NUMERAL",
                                                            "par",
                                                            "STRING",
                                                            "assert",
                                                            "check-sat",
                                                            "check-sat-assuming",
                                                            "declare-const",
                                                            "declare-datatype",
                                                            "declare-datatypes",
                                                            "declare-fun",
                                                            "declare-sort",
                                                            "define-fun",
                                                            "define-fun-rec",
                                                            "define-funs-rec",
                                                            "define-sort",
                                                            "echo",
                                                            "exit",
                                                            "get-assertions",
                                                            "get-assignment",
                                                            "get-info",
                                                            "get-model",
                                                            "get-option",
                                                            "get-proof",
                                                            "get-unsat-assumptions",
                                                            "get-unsat-core",
                                                            "get-value",
                                                            "pop",
                                                            "push",
                                                            "reset",
                                                            "reset-assertions",
                                                            "set-info",
                                                            "set-logic",
                                                            "set-option"};
    if (std::isdigit(static_cast<unsigned char>(name[0])) || s_reserved.count(name)) return false;
    for (const char c : name) {
        if (!std::isalnum(static_cast<unsigned char>(c))
            && (c == '\0' || !std::strchr("~!@$%^&*_-+=<>.?/", c))) {
            return false;
        }
    }
    return true;
}

// Reads values of a sort written as emitType() writes one, (_ BitVec <width>) or (Array
// (_ BitVec <index>) <element sort>), as solvers write them in a model: literals, constant arrays
// with stores into them, and lets naming any of these. A sort is named by the position in the
// sort's tokens where it opens.
class VlSMTValueReader final {
    // Bounds the stack a malformed reply can use; solvers nest lets in a let's term, which is
    // read without recursion, so only a dimension or a let in a bound term adds a level
    static constexpr int MAX_DEPTH = 100;
    const std::vector<std::string>& m_tokens;  // The reply's tokens
    const std::vector<std::string>& m_sort;  // The array sort's tokens, as emitType() writes it
    // Bound terms by where they start, which names the scope they are read in
    std::map<std::pair<size_t, size_t>, bool> m_validAt;  // (Term, sort) -> whether a value of it
    // Name -> terms it binds, innermost last
    std::unordered_map<std::string, std::vector<size_t>> m_names;
    // Token -> one past the term starting there, so skipping a term costs nothing
    const std::vector<size_t> m_ends;
    const std::vector<size_t> m_sortEnds;  // The same for the sort's tokens

    const std::string& tok(size_t i) const { return smtToken(m_tokens, i); }
    size_t termEnd(size_t i) const { return i < m_ends.size() ? m_ends[i] : i; }
    // Whether a let names a variable this, so it no longer names a function
    bool bound(const std::string& name) const {
        const auto it = m_names.find(name);
        return it != m_names.end() && !it->second.empty();
    }
    bool isArray(size_t s) const { return smtToken(m_sort, s + 1) == "Array"; }
    // An array sort's (Array <index sort> <element sort>): its index sort, (_ BitVec <width>)
    static size_t indexSort(size_t s) { return s + 2; }
    size_t elementSort(size_t s) const { return m_sortEnds[indexSort(s)]; }

    // Reads at m_tokens[i] lets and the term they scope, a value of the sort at s. Solvers nest
    // one let per shared term, so nested lets are read without recursion, and each bound term
    // is checked once against every sort where it is bound, the names it uses being checked
    // already, so a chain of names costs no stack either. A term starting at a given token is
    // always read in the same scope, so a check is kept for every read of that let.
    bool readLets(size_t& i, size_t s, int depth) {
        std::vector<std::map<std::string, size_t>> lets;  // Each let's names -> bound terms
        bool ok = true;
        while (ok && tok(i) == "(" && tok(i + 1) == "let") {
            i += 2;
            ok = tok(i++) == "(" && tok(i) == "(";  // At least one binding
            lets.emplace_back();
            while (ok && tok(i) == "(") {
                const std::string& name = tok(++i);
                const size_t begin = i + 1;
                bool valid = false;  // Of some sort, used or not, as it goes back to the solver
                for (size_t t = 0; t < m_sort.size(); ++t) {
                    if (m_sort[t] != "(") continue;
                    auto it = m_validAt.find({begin, t});
                    if (it == m_validAt.end()) {
                        size_t j = begin;
                        const bool validAt = read(j, t, depth + 1);
                        it = m_validAt.emplace(std::make_pair(begin, t), validAt).first;
                    }
                    valid = valid || it->second;
                }
                i = termEnd(begin);
                ok = valid && smtSimpleSymbol(name) && lets.back().emplace(name, begin).second
                     && tok(i++) == ")";
            }
            ok = ok && tok(i++) == ")";
            // Bound only now, for the term: let binds in parallel
            for (const auto& binding : lets.back())
                m_names[binding.first].push_back(binding.second);
        }
        ok = ok && read(i, s, depth + 1);
        for (const auto& let : lets) {
            ok = ok && tok(i++) == ")";
            for (const auto& binding : let) m_names[binding.first].pop_back();
        }
        return ok;
    }

public:
    VlSMTValueReader(const std::vector<std::string>& tokens, const std::vector<std::string>& sort)
        : m_tokens{tokens}
        , m_sort{sort}
        , m_ends{smtTermEnds(tokens)}
        , m_sortEnds{smtTermEnds(sort)} {}

    // Reads at m_tokens[i] a value of the sort at s
    bool read(size_t& i, size_t s, int depth) {
        if (depth > MAX_DEPTH) return false;
        if (tok(i) != "(") {
            const auto it = m_names.find(tok(i));
            if (it != m_names.end() && !it->second.empty()) {
                ++i;
                const auto valid = m_validAt.find({it->second.back(), s});
                return valid != m_validAt.end() && valid->second;
            }
        } else if (tok(i + 1) == "let") {
            return readLets(i, s, depth);
        }
        // (_ BitVec <width>): a plain or indexed literal
        if (!isArray(s)) {
            if (tok(i) == "(" && bound(tok(i + 2))) return false;
            return smtReadLiteral(m_tokens, i, std::atoi(smtToken(m_sort, s + 3).c_str()));
        }
        // Stores into a constant array, read without recursion so a long chain costs no stack
        size_t stores = 0;
        for (; tok(i) == "(" && tok(i + 1) == "store" && !bound("store"); i += 2) ++stores;
        if (stores) {
            if (!read(i, s, depth + 1)) return false;
        } else {
            // ((as const <sort>) <element>)
            for (const char* const token : {"(", "(", "as", "const"}) {
                if (tok(i++) != token) return false;
            }
            if (bound("const")) return false;
            for (size_t k = s; k < m_sortEnds[s]; ++k) {
                if (tok(i++) != m_sort[k]) return false;
            }
            if (tok(i++) != ")" || !read(i, elementSort(s), depth + 1) || tok(i++) != ")") {
                return false;
            }
        }
        for (; stores; --stores) {
            if (!read(i, indexSort(s), depth + 1) || !read(i, elementSort(s), depth + 1)
                || tok(i++) != ")") {
                return false;
            }
        }
        return true;
    }
};

// True if val is a value of an array of sort, as emitType() writes it
static bool smtArrayOfSort(const std::string& val, const std::string& sort) {
    const std::vector<std::string> tokens = smtTokens(val);
    const std::vector<std::string> sortTokens = smtTokens(sort);
    size_t i = 0;
    return VlSMTValueReader{tokens, sortTokens}.read(i, 0, 0) && i == tokens.size();
}

// val must have passed validSMTNum
static void parseSMTNum(int obits, WDataOutP owp, const std::string& val) {
    size_t i = val.find('#') + 1;
    switch (val[i++]) {
    case 'b': _vl_vsss_based(owp, obits, 1, &val[i], 0, val.size() - i); break;
    case 'o': _vl_vsss_based(owp, obits, 3, &val[i], 0, val.size() - i); break;
    default: _vl_vsss_based(owp, obits, 4, &val[i], 0, val.size() - i); break;
    }
}

// The elements val, a model's value of a one-dimensional array of bit-vector indices of
// indexWidth (at most 32) bits and elements of elementWidth bits, sets: the value of each
// index stored, the outermost store of an index winning as in the array, and the constant
// array's element for the others. Read as solvers write one, stores into a constant array
// through lets naming any part of it or any value in it: each let must bind a name of its
// own, so a name stands for one term, followed once. False for any other form, such as a
// function as-array, or a value that is no literal of its width.
static bool smtArrayStores(const std::string& val, int indexWidth, int elementWidth,
                           std::unordered_map<IData, std::string>& storesr,
                           std::string& defaultr) {
    const std::vector<std::string> tokens = smtTokens(val);
    std::ostringstream sort;
    sort << "(Array (_ BitVec " << indexWidth << ") (_ BitVec " << elementWidth << "))";
    const std::vector<std::string> sortTokens = smtTokens(sort.str());
    size_t end = 0;
    // Of the sort, with every name it uses bound, so the walk below needs no checks of its own
    if (!VlSMTValueReader{tokens, sortTokens}.read(end, 0, 0) || end != tokens.size()) {
        return false;
    }
    const std::vector<size_t> ends = smtTermEnds(tokens);
    const auto tok = [&](size_t i) -> const std::string& { return smtToken(tokens, i); };
    std::unordered_map<std::string, size_t> bound;  // Let name -> where its term starts
    for (size_t i = 0; i + 1 < tokens.size(); ++i) {
        if (tok(i) != "(" || tok(i + 1) != "let") continue;
        for (size_t b = i + 3; tok(b) == "("; b = ends[b]) {
            if (!bound.emplace(tok(b + 1), b + 2).second) return false;
        }
    }
    // Where the term a name stands for starts, through names bound to names, or npos for a
    // chain longer than the names bound. Each name is then bound to where its chain ends, so
    // a chain is followed once.
    const auto resolve = [&](size_t i) {
        std::vector<std::string> chain;
        for (auto it = bound.find(tok(i)); tok(i) != "(" && it != bound.end();
             it = bound.find(tok(i))) {
            if (chain.size() > bound.size()) return std::string::npos;
            chain.push_back(tok(i));
            i = it->second;
        }
        for (const std::string& name : chain) bound[name] = i;
        return i;
    };
    // The literal of width bits a scalar term at i stands for, through names and lets, and
    // written as binary if indexed; false if there is none
    const auto literalAt = [&](size_t i, int width, std::string& literalr) {
        for (i = resolve(i); i != std::string::npos && tok(i) == "(" && tok(i + 1) == "let";) {
            i = resolve(ends[i + 2]);  // Its term, after its bindings
        }
        if (i == std::string::npos) return false;
        literalr = tok(i);
        if (literalr == "(") literalr += tok(i + 1) + ' ' + tok(i + 2) + ' ' + tok(i + 3) + ')';
        return smtLiteralOfWidth(literalr, static_cast<size_t>(width));
    };
    std::string index;
    std::string value;
    for (size_t i = 0;;) {
        i = resolve(i);
        if (i == std::string::npos) return false;
        if (tok(i + 1) == "let") {
            i = ends[i + 2];  // Its term, after its bindings
        } else if (tok(i + 1) == "store") {
            const size_t indexAt = ends[i + 2];
            const bool literals = literalAt(indexAt, indexWidth, index)
                                  && literalAt(ends[indexAt], elementWidth, value);
            if (!literals) return false;
            IData key = 0;
            parseSMTNum(indexWidth, WDataOutP::external(&key), index);
            storesr.emplace(key, value);  // Kept if an outer store set the index already
            i += 2;
        } else {
            // ((as const <sort>) <element>)
            return literalAt(ends[i + 1], elementWidth, defaultr);
        }
    }
}

void VlRandomVar::set(const std::string& idx, const std::string& val) const {
    VlWide<VL_WQ_WORDS_E> qowp;
    VL_SET_WQ(qowp, 0ULL);
    WDataOutP owp = qowp;
    const int obits = width();
    VlWide<VL_WQ_WORDS_E> qiwp;
    VL_SET_WQ(qiwp, 0ULL);
    if (!idx.empty()) parseSMTNum(64, qiwp, idx);
    const int nidx = qiwp[0];
    if (obits > VL_QUADSIZE) owp = WDataOutP::external(reinterpret_cast<EData*>(datap(nidx)));
    parseSMTNum(obits, owp, val);

    if (obits <= VL_BYTESIZE) {
        CData* const p = static_cast<CData*>(datap(nidx));
        *p = VL_CLEAN_II(obits, obits, owp[0]);
    } else if (obits <= VL_SHORTSIZE) {
        SData* const p = static_cast<SData*>(datap(nidx));
        *p = VL_CLEAN_II(obits, obits, owp[0]);
    } else if (obits <= VL_IDATASIZE) {
        IData* const p = static_cast<IData*>(datap(nidx));
        *p = VL_CLEAN_II(obits, obits, owp[0]);
    } else if (obits <= VL_QUADSIZE) {
        QData* const p = static_cast<QData*>(datap(nidx));
        *p = VL_CLEAN_QQ(obits, obits, VL_SET_QW(owp));
    } else {
        _vl_clean_inplace_w(obits, owp);
    }
}

void VlRandomizer::randomConstraint(std::ostream& os, VlRNG& rngr, int bits,
                                    const std::vector<std::string>* layerVarsp) {
    // layerVarsp scopes sampling to the current phase's own layer, so a
    // phased solve's diversity constraint can't be built entirely out of a
    // later phase's (still-unsolved) variable instead of this one's.
    std::vector<const VlRandomVar*>& vars = m_randomConstraintVars;
    vars.clear();
    int varBits = 0;
    if (layerVarsp) {
        for (const auto& name : *layerVarsp) {
            // buildSolveLayers() only ever adds a name after confirming it names a variable
            const VlRandomVar* const varp = solveBeforeVarp(name);
            assert(varp);
            vars.push_back(varp);
            varBits += varp->totalWidth();
        }
    } else {
        for (const auto& var : m_vars) {
            vars.push_back(var.second.get());
            varBits += var.second->totalWidth();
        }
    }

    if (varBits == 0) {
        // Nothing to sample (e.g. a still-unsized queue/dynamic array, in a
        // layer or the whole class) -- tautology instead of the degenerate
        // empty-operand expression the loop below would otherwise build.
        os << "(= #b1 #b1)";
        return;
    }
    const IData hash = VL_RANDOM_RNG_I(rngr) & ((1 << bits) - 1);
    os << "(= #b";
    for (int i = bits - 1; i >= 0; i--) os << (VL_BITISSET_I(hash, i) ? '1' : '0');
    if (bits > 1) os << " (concat";
    for (int i = 0; i < bits; ++i) {
        IData varBitsLeft = varBits;
        IData varBitsWant = (varBits + 1) / 2;
        if (varBits > 2) os << " (bvxor";
        for (const auto& varp : vars) {  // LCOV_EXCL_BR_LINE - reservoir-sampling below
                                         // always forces its last pick before exhausting vars
            for (int j = 0; j < varp->totalWidth(); j++, varBitsLeft--) {
                const bool doEmit = (VL_RANDOM_RNG_I(rngr) % varBitsLeft) < varBitsWant;
                if (doEmit) {
                    varp->emitExtract(os, j);
                    if (--varBitsWant == 0) break;
                }
            }
            if (varBitsWant == 0) break;
        }
        if (varBits > 2) os << ')';
    }
    if (bits > 1) os << ')';
    os << ')';
}

size_t VlRandomizer::hashConstraints(const std::vector<std::string>& extras,
                                     bool randcOnly) const {
    size_t h = 0;
    for (size_t i = 0; i < m_constraints.size(); ++i) {
        if (randcOnly) {
            // Only a change of the constraints on a randc variable restarts its cycle
            // (IEEE 1800-2023 18.4.2), not a state value changing in another constraint
            const auto beginIt
                = m_constraintVarNames.begin() + (i ? m_constraintVarEnds[i - 1] : 0);
            const auto endIt = m_constraintVarNames.begin() + m_constraintVarEnds[i];
            if (std::none_of(beginIt, endIt, [this](const char* namep) {
                    return m_randcVarNames.count(namep) != 0;
                })) {
                continue;
            }
        }
        h ^= std::hash<std::string>{}(m_constraints[i]) + 0x9e3779b9 + (h << 6) + (h >> 2);
        // The tables it calls, as its text names them but does not hold them
        h ^= m_constraintTablesHash[i] + 0x9e3779b9 + (h << 6) + (h >> 2);
    }
    for (const auto& c : extras) {
        h ^= std::hash<std::string>{}(c) + 0x9e3779b9 + (h << 6) + (h >> 2);
    }
    // Only the randc variables themselves, not others a randomize() with also registers
    for (const auto& var : m_vars) {
        if (randcOnly && !m_randcVarNames.count(var.first)) continue;
        h ^= std::hash<std::string>{}(var.first) + 0x9e3779b9 + (h << 6) + (h >> 2);
        h ^= std::hash<int>{}(var.second->width()) + 0x9e3779b9 + (h << 6) + (h >> 2);
        h ^= std::hash<int>{}(var.second->dimension()) + 0x9e3779b9 + (h << 6) + (h >> 2);
        if (randcOnly && var.second->dimension() > 0) {
            // The elements of a randc array, by their keys as VlRandomArrayVarTemplate::datap()
            // finds them, so a resized array gets a different hash
            int elements = 0;
            while (m_arr_vars.count({var.first, elements})) ++elements;
            h ^= std::hash<int>{}(elements) + 0x9e3779b9 + (h << 6) + (h >> 2);
        }
    }
    // Keys are one per array element, so a resized queue gets a different hash.
    if (!randcOnly) {
        for (const auto& elem : m_arr_vars) {
            h ^= std::hash<std::string>{}(elem.first.first) + 0x9e3779b9 + (h << 6) + (h >> 2);
            h ^= std::hash<int>{}(elem.first.second) + 0x9e3779b9 + (h << 6) + (h >> 2);
        }
    }
    return h;
}

// The solver term of element j of var, which keys the used values of a randc variable, as
// each element of a randc array cycles on its own (IEEE 1800-2023 18.4)
static std::string randcElementTerm(const VlRandomVar& var, int j) {
    std::ostringstream termOs;
    var.emitElement(termOs, j);
    return termOs.str();
}

void VlRandomizer::emitRandcExclusions(std::ostream& os) const {
    for (const auto& name : m_randcVarNames) {
        const auto varIt = m_vars.find(name);
        if (varIt == m_vars.end()) continue;
        const VlRandomVar& var = *varIt->second;
        for (int j = 0; j < var.totalWidth() / var.width(); ++j) {
            const std::string term = randcElementTerm(var, j);
            const auto usedIt = m_randcUsedValues.find(term);
            if (usedIt == m_randcUsedValues.end()) continue;
            for (const uint64_t val : usedIt->second) {
                os << "(assert (not (=" << term << " (_ bv" << val << " " << var.width()
                   << "))))\n";
            }
        }
    }
}

static uint64_t readVarValueU64(const void* datap, int width) {
    if (width <= VL_BYTESIZE) return *static_cast<const CData*>(datap);
    if (width <= VL_SHORTSIZE) return *static_cast<const SData*>(datap);
    if (width <= VL_IDATASIZE) return *static_cast<const IData*>(datap);
    if (width <= VL_QUADSIZE) return *static_cast<const QData*>(datap);
    return 0;
}

void VlRandomizer::recordRandcValues() {
    // Only the final solve, of the final function-call solve round, picks the values
    if (funcPreRound() || m_sizeSolve) return;
    for (const auto& name : m_randcVarNames) {
        const auto varIt = m_vars.find(name);
        if (varIt == m_vars.end()) continue;
        const VlRandomVar& var = *varIt->second;
        for (int j = 0; j < var.totalWidth() / var.width(); ++j) {
            m_randcUsedValues[randcElementTerm(var, j)].insert(
                readVarValueU64(var.datap(j), var.width()));
        }
    }
}

bool VlRandomizer::isFrozenVar(const std::string& name, const VlRandomVar& var) const {
    if (!var.randModeIdxNone()) {
        const VlQueue<CData>* const modep
            = m_staticVars.count(name) ? m_static_randmodep : m_randmodep;
        // modep is never null in practice, the fallthrough matches the return below
        if (VL_UNCOVERABLE(!modep)) return m_disabledVars.count(name) != 0;
        if (!modep->at(var.randModeIdx())) return true;
    }
    // Struct/nested members are disabled via m_disabledVars.
    // They have no randModeIdx of their own.
    return m_disabledVars.count(name) != 0;
}

bool VlRandomizer::hasFrozenVar() const {
    // A disabled var may be another class's static, with no rand_mode in this class
    const bool mayBeFrozen = m_randmodep || m_static_randmodep || !m_disabledVars.empty();
    if (!mayBeFrozen) return false;
    for (const auto& var : m_vars) {
        if (isFrozenVar(var.first, *var.second)) return true;
    }
    return false;
}

void VlRandomizer::hideUnnamedFrozen(
    std::map<std::string, std::shared_ptr<const VlRandomVar>>& hiddenr) {
    // A solve-before ordering reads the values of its layers through their names, an element
    // of an array by a name of its own
    if (m_heldLookups.empty() || !m_solveBefore.empty()) return;
    // The variables the constraints name whatever their rand_mode, as the compiler lists them
    std::unordered_set<std::string> named{m_constraintVarNames.begin(),
                                          m_constraintVarNames.end()};
    named.insert(m_softVarNames.begin(), m_softVarNames.end());
    for (const auto& unique : m_uniqueArrays) {
        named.insert(unique.second.begin(), unique.second.end());
    }
    for (const auto& pin : m_frozenPins) named.insert(pin.first);
    for (const std::string& name : m_heldLookups) {
        const auto it = m_vars.find(name);
        if (it == m_vars.end() || !isFrozenVar(name, *it->second) || named.count(name)
            || m_randcVarNames.count(name) || m_sizeVars.count(name)) {
            continue;
        }
        hiddenr.emplace(name, it->second);
        m_vars.erase(it);
    }
}

bool VlRandomizer::next_check_only(VlRNGReseeds& rngr) { return nextRandomize(rngr, true); }

bool VlRandomizer::next(VlRNGReseeds& rngr) { return nextRandomize(rngr, false); }

bool VlRandomizer::next_size(VlRNGReseeds& rngr) { return nextRandomize(rngr, false, true); }

// Bytes of an element of var, whole, as set() writes it
static size_t elemBytes(const VlRandomVar& var) {
    const int w = var.width();
    return w <= VL_BYTESIZE    ? sizeof(CData)
           : w <= VL_SHORTSIZE ? sizeof(SData)
           : w <= VL_IDATASIZE ? sizeof(IData)
           : w <= VL_QUADSIZE  ? sizeof(QData)
                               : VL_WORDS_I(w) * sizeof(EData);
}

// Append the name and the bytes of all elements of var to valuesr
void VlRandomizer::keepValues(const VlRandomVar& var, KeptValues& valuesr) {
    const size_t bytes = elemBytes(var);
    std::string values;
    for (int j = 0; j < var.totalWidth() / var.width(); ++j) {
        values.append(static_cast<const char*>(var.datap(j)), bytes);
    }
    valuesr.emplace_back(var.name(), std::move(values));
}

void VlRandomizer::keepVars(KeptValues& valuesr) const {
    // Not those with rand_mode off, which the solve does not set and callbacks may change or
    // free (IEEE 1800-2023 18.8)
    const auto arrVarsp = std::make_shared<const ArrayInfoMap>(m_arr_vars);
    for (const auto& var : m_vars) {
        if (isFrozenVar(var.first, *var.second)) continue;
        if (var.second->dimension() > 0) var.second->setArrayInfo(arrVarsp);
        keepValues(*var.second, valuesr);
    }
}

void VlRandomizer::setValues(const KeptValues& values) const {
    // Through the storage registered last, as arrays resized since may have moved, by element
    // position, skipping the elements an array no longer holds, and the variables no longer
    // registered: those of an object a callback detached, whose handle it set to null
    for (const auto& kept : values) {
        const auto it = m_vars.find(kept.first);
        if (it == m_vars.end()) continue;
        const VlRandomVar& var = *it->second;
        const size_t bytes = elemBytes(var);
        for (size_t j = 0; j < kept.second.size() / bytes; ++j) {
            void* datap;
            if (var.dimension() > 0) {
                const auto elemIt = m_arr_vars.find({kept.first, static_cast<int>(j)});
                if (elemIt == m_arr_vars.end()) continue;
                datap = elemIt->second->m_datap;
            } else {
                datap = var.datap(0);
            }
            std::memcpy(datap, kept.second.data() + j * bytes, bytes);
        }
    }
}

void VlRandomizer::keep_solution() { keepVars(m_solution); }

void VlRandomizer::restore_solution() {
    setValues(m_solution);
    m_solution.clear();
}

void VlRandomizer::keep_prior() {
    // Once per call: later function-call solve rounds must not overwrite it
    if (m_prior.empty()) {
        keepVars(m_prior);
        m_priorRandc = m_randcUsedValues;
    }
}

void VlRandomizer::end_prior(bool ok) {
    // A failed call leaves the values and the randc cycles (IEEE 1800-2023 18.6.3)
    if (!ok) {
        setValues(m_prior);
        m_randcUsedValues.swap(m_priorRandc);
    }
    m_prior.clear();
    m_priorRandc.clear();
}

void VlRandomizer::keepRoundValues(const VlRandomVar& var) {
    if (funcPreRound() && m_roundKept.insert(var.name()).second) {
        keepValues(var, m_roundValues);
    }
}

// Normalize a union without changing its set of legal values. Weights are only
// used by the original dist buckets, never by the intersected membership domains.
VlRandomizer::FastRanges VlRandomizer::fastUnion(FastRanges ranges) {
    std::sort(ranges.begin(), ranges.end(),
              [](const FastRange& a, const FastRange& b) { return a.lo < b.lo; });
    FastRanges result;
    for (const FastRange& range : ranges) {
        if (!result.empty()
            && (result.back().hi == std::numeric_limits<QData>::max()
                || range.lo <= result.back().hi + 1)) {
            result.back().hi = std::max(result.back().hi, range.hi);
        } else {
            result.push_back({range.lo, range.hi, 1, 1});
        }
    }
    return result;
}

// b is a sorted, disjoint membership domain.
VlRandomizer::FastRanges VlRandomizer::fastIntersect(const FastRanges& a, const FastRanges& b) {
    FastRanges result;
    for (const FastRange& range : a) {
        auto it = std::lower_bound(b.begin(), b.end(), range.lo,
                                   [](const FastRange& r, QData lo) { return r.hi < lo; });
        for (; it != b.end() && it->lo <= range.hi; ++it) {
            result.push_back({std::max(range.lo, it->lo), std::min(range.hi, it->hi), range.weight,
                              range.scale});
        }
    }
    return result;
}

// Uniform bounded draws without modulo bias. The finite 64-bit bound is
// nonzero. This does not touch the solver or the thread's global RNG.
static QData vl_fastBelow(VlRNG& rngr, QData bound) {
    const QData threshold = -bound % bound;
    QData value;
    do { value = VL_RANDOM_RNG_Q(rngr); } while (value < threshold);
    return value % bound;
}

// High 64 bits of the 128-bit product a * b.
static QData vl_fastMulHi(QData a, QData b) {
    const QData mask = VL_MASK_Q(VL_IDATASIZE);
    const QData low = (a & mask) * (b & mask);
    const QData mid1 = (a >> VL_IDATASIZE) * (b & mask);
    const QData mid2 = (a & mask) * (b >> VL_IDATASIZE);
    const QData carry = ((low >> VL_IDATASIZE) + (mid1 & mask) + (mid2 & mask)) >> VL_IDATASIZE;
    return (a >> VL_IDATASIZE) * (b >> VL_IDATASIZE) + (mid1 >> VL_IDATASIZE)
           + (mid2 >> VL_IDATASIZE) + carry;
}

// Binary digits of a 128-bit numerator divided by a 64-bit divisor, most
// significant first: the numerator's remaining bits, then fraction bits.
struct VlFastQuotient final {
    QData hi = 0;  // Numerator bits not yet consumed, left-aligned
    QData lo = 0;
    QData divisor = 1;
    QData remainder = 0;
    bool nextBit() {
        const QData in = hi >> (VL_QUADSIZE - 1);
        hi = (hi << 1) | (lo >> (VL_QUADSIZE - 1));
        lo <<= 1;
        // remainder * 2 + in >= divisor, without overflow
        const bool carry = remainder >= divisor - remainder - in;
        remainder = carry ? remainder - (divisor - remainder - in) : 2 * remainder + in;
        return carry;
    }
    bool isZero() const { return !(hi | lo | remainder); }
    // Significant bits in the unconsumed numerator
    int bits() const {
        return hi ? VL_QUADSIZE + static_cast<int>(VL_MOSTSETBITP1_Q(hi))
                  : static_cast<int>(VL_MOSTSETBITP1_Q(lo));
    }
    // Consume count < 2 * VL_QUADSIZE numerator bits that are zero
    void shiftLeft(int count) {
        if (count >= VL_QUADSIZE) {
            hi = lo << (count - VL_QUADSIZE);
            lo = 0;
        } else {
            // Two right shifts avoid an undefined shift by VL_QUADSIZE when count is 0
            hi = (hi << count) | ((lo >> (VL_QUADSIZE - 1 - count)) >> 1);
            lo <<= count;
        }
    }
};

// One dist item's feasible values, a contiguous span of ranks in the domain.
// Its mass, massCount * weight / divisor, is scaled into whole units plus, when
// the scaled mass is not whole, a final unit accepted with probability equal
// to the fraction whose binary digits remain in fraction.
struct VlFastBucket final {
    QData first = 0;  // Rank of the first feasible value
    QData count = 0;  // Number of feasible values
    QData massCount = 0;  // Values the mass counts, feasible or not; 0 is 2^64
    QData weight = 0;
    QData divisor = 0;
    QData units = 0;
    QData end = 0;  // Cumulative units, including any final partial unit
    VlFastQuotient fraction{};
};

static constexpr QData s_fastMax = std::numeric_limits<QData>::max();

// Exact integer masses over the least common denominator, when they fit.
static QData vl_fastExactMasses(std::vector<VlFastBucket>& buckets) {
    QData denominator = 1;
    for (const VlFastBucket& bucket : buckets) {
        QData a = denominator;
        QData b = bucket.divisor;
        while (b) {
            const QData remainder = a % b;
            a = b;
            b = remainder;
        }
        const QData factor = bucket.divisor / a;
        if (factor > s_fastMax / denominator) return 0;
        denominator *= factor;
    }
    QData total = 0;
    for (VlFastBucket& bucket : buckets) {
        const QData scale = denominator / bucket.divisor;
        if (bucket.weight > s_fastMax / scale) return 0;
        const QData weight = bucket.weight * scale;
        if (!bucket.massCount || bucket.massCount > s_fastMax / weight) return 0;
        bucket.units = bucket.massCount * weight;
        if (bucket.units > s_fastMax - total) return 0;
        total += bucket.units;
        bucket.end = total;
    }
    return total;
}

// Masses scaled by a common power of two when no 64-bit common denominator
// exists. Long division of each 128-bit massCount * weight by the divisor gives
// its whole scaled units; the remaining quotient digits are the fraction of
// its final unit. With every mass below 2^maxBits, the shift keeps the total
// below 2^63 + buckets and the largest mass at least 2^60 / buckets units.
static QData vl_fastScaledMasses(std::vector<VlFastBucket>& buckets) {
    // Every mass < 2^maxBits; buckets is nonempty (asserted in fastSample)
    int maxBits = std::numeric_limits<int>::min();
    for (VlFastBucket& bucket : buckets) {
        VlFastQuotient& fraction = bucket.fraction;
        fraction = bucket.massCount
                       ? VlFastQuotient{vl_fastMulHi(bucket.massCount, bucket.weight),
                                        bucket.massCount * bucket.weight, bucket.divisor}
                       : VlFastQuotient{bucket.weight, 0, bucket.divisor};
        const int bits = fraction.bits() - static_cast<int>(VL_MOSTSETBITP1_Q(bucket.divisor)) + 1;
        maxBits = std::max(maxBits, bits);
    }
    // At least -2 * VL_QUADSIZE, as maxBits <= 2 * VL_QUADSIZE and buckets.size() < 2^63
    const int shift = 63 - maxBits - static_cast<int>(VL_MOSTSETBITP1_Q(buckets.size()));
    QData total = 0;
    for (VlFastBucket& bucket : buckets) {
        VlFastQuotient& fraction = bucket.fraction;
        // The quotient digits weighing at least 2^-shift are the whole units.
        // Leading zero numerator bits add nothing, so skip them directly.
        int digits = 2 * VL_QUADSIZE + shift;
        const int skip = std::min(digits, 2 * VL_QUADSIZE - fraction.bits());
        fraction.shiftLeft(skip);
        for (bucket.units = 0, digits -= skip; digits; --digits) {
            bucket.units = 2 * bucket.units + fraction.nextBit();
        }
        total += bucket.units + !fraction.isZero();
        bucket.end = total;
    }
    return total;
}

// True with probability equal to the binary fraction whose digits fraction yields.
static bool vl_fastBernoulli(VlRNG& rngr, VlFastQuotient fraction) {
    while (true) {
        QData bits = VL_RANDOM_RNG_Q(rngr);
        for (int i = 0; i < VL_QUADSIZE; ++i, bits <<= 1) {
            const bool digit = fraction.nextBit();
            if (digit != static_cast<bool>(bits >> (VL_QUADSIZE - 1))) return digit;
        }
    }
}

bool VlRandomizer::fastSample(VlRNG& rngr, const FastRanges& domain, const FastConstraint* distp,
                              QData& valuer) {
    // A full, single power-of-two range has an unbiased procedural pick already.
    // Reuse it without an extra draw, preserving width-independent global RNG use.
    if (distp && distp->hasProposal && distp->ranges.size() == 1 && domain.size() == 1
        && domain[0].lo == distp->ranges[0].lo && domain[0].hi == distp->ranges[0].hi) {
        const QData count = domain[0].hi - domain[0].lo + 1;
        if (count && !(count & (count - 1)) && distp->proposal >= domain[0].lo
            && distp->proposal <= domain[0].hi) {
            valuer = distp->proposal;
            return true;
        }
    }
    // Number the legal values in order. Each dist item then covers one span of
    // ranks, however many domain ranges it crosses.
    std::vector<QData> prefix;
    prefix.reserve(domain.size() + 1);
    prefix.push_back(0);
    for (const FastRange& range : domain) {
        const QData count = range.hi - range.lo + 1;
        // Disjoint, non-adjacent ranges total 2^64 values only as one full range
        if (!count) return false;
        prefix.push_back(prefix.back() + count);
    }
    std::vector<VlFastBucket> buckets;
    if (distp) {
        // Rank of key, given the first domain range that does not end before key
        const auto rankAt = [&](FastRanges::const_iterator it, QData key, bool inclusive) {
            const QData before = prefix[it - domain.begin()];
            return it != domain.end() && key >= it->lo ? before + (key - it->lo) + inclusive
                                                       : before;
        };
        const auto endsBefore = [](const FastRange& r, QData key) { return r.hi < key; };
        buckets.reserve(distp->ranges.size());
        for (const FastRange& range : distp->ranges) {
            const auto loIt = std::lower_bound(domain.begin(), domain.end(), range.lo, endsBefore);
            const auto hiIt = loIt == domain.end() || range.hi <= loIt->hi
                                  ? loIt
                                  : std::lower_bound(loIt, domain.end(), range.hi, endsBefore);
            const QData first = rankAt(loIt, range.lo, false);
            const QData count = rankAt(hiIt, range.hi, true) - first;
            if (!count) continue;
            // IEEE 1800-2023 18.5.3 weighs an item as a whole, counting values other
            // constraints exclude; 1800-2017 18.5.4 weighs each surviving value.
            if (distp->rangeMass) {
                buckets.push_back({first, count, range.scale, range.weight, 1});
            } else {
                buckets.push_back({first, count, count, range.weight, range.scale});
            }
        }
        assert(!buckets.empty());  // The domain is a subset of the retained dist's union
    } else {
        buckets.push_back({0, prefix.back(), prefix.back(), 1, 1});
    }
    QData total = vl_fastExactMasses(buckets);
    if (!total) total = vl_fastScaledMasses(buckets);
    // Only a final partial unit can reject, below B^2 / 2^60 of proposals
    while (true) {
        const QData pick = vl_fastBelow(rngr, total);
        const auto it = std::upper_bound(buckets.begin(), buckets.end(), pick,
                                         [](QData p, const VlFastBucket& b) { return p < b.end; });
        const QData unit = pick - (it == buckets.begin() ? 0 : (it - 1)->end);
        QData offset;
        if (unit < it->units) {
            // Whole units map in order onto the feasible values when they divide
            // evenly among them; otherwise the value is drawn separately.
            offset = (it->units % it->count) ? vl_fastBelow(rngr, it->count)
                                             : unit / (it->units / it->count);
        } else {
            if (!vl_fastBernoulli(rngr, it->fraction)) continue;
            offset = vl_fastBelow(rngr, it->count);
        }
        const QData rank = it->first + offset;
        const size_t i = std::upper_bound(prefix.begin(), prefix.end(), rank) - prefix.begin() - 1;
        valuer = domain[i].lo + (rank - prefix[i]);
        return true;
    }
}

// A hard singleton view fixes exactly those physical bits. It does not
// consume probability mass or silently pin any bits outside that view.
bool VlRandomizer::fastPinned(const FastConstraint& constraint) {
    return !constraint.isSoft && !constraint.isDist && !constraint.isEnum
           && constraint.ranges.size() == 1 && constraint.ranges[0].lo == constraint.ranges[0].hi;
}

bool VlRandomizer::fastView(FastDomain& domain) {
    const QData physicalMask = VL_MASK_Q(domain.varp->width());
    if (!domain.viewWidth) {
        const QData freeMask = physicalMask & ~domain.pinMask;
        if (!freeMask) {
            domain.viewWidth = domain.varp->width();
        } else {
            const QData first = freeMask & -freeMask;
            domain.viewLsb = VL_COUNTONES_Q(first - 1);
            const QData shifted = freeMask >> domain.viewLsb;
            if (shifted & (shifted + 1)) return false;  // More than one free window
            domain.viewWidth = VL_COUNTONES_Q(shifted);
        }
    }
    const QData mask = VL_MASK_Q(domain.viewWidth);
    const QData viewMask = mask << domain.viewLsb;
    const QData outside = physicalMask & ~viewMask;
    if ((domain.pinMask & outside) != outside) return false;
    const QData inside = domain.pinMask & viewMask;
    if (inside && inside != viewMask) return false;  // Gaps need the solver
    if (domain.pinConflict) return true;  // Preserve an empty hard domain
    if (inside) {
        QData value = (domain.pinBits >> domain.viewLsb) & mask;
        if (domain.isSigned) value ^= QData{1} << (domain.viewWidth - 1);
        domain.ranges.push_back({value, value, 1, 1});
    } else {
        domain.ranges.push_back({0, mask, 1, 1});
    }
    return true;
}

bool VlRandomizer::fastDomains(std::vector<FastDomain>& domains,
                               std::unordered_map<void*, size_t>& indices) {
    std::unordered_set<void*> enumNeeded;
    for (const auto& namedVar : m_vars) {
        const VlRandomVar* const varp = namedVar.second.get();
        if (varp->dimension() || varp->width() <= 0 || varp->width() > VL_QUADSIZE) return false;
        // Two symbolic names for one location require the full alias checks.
        if (!indices.emplace(varp->datap(0), domains.size()).second) return false;
        if (m_enumDomains.count(namedVar.first)) enumNeeded.insert(varp->datap(0));
        FastDomain domain;
        domain.varp = varp;
        domains.push_back(std::move(domain));
    }
    for (const FastConstraint& constraint : m_fastConstraints) {
        const auto it = indices.find(constraint.datap);
        if (it == indices.end()) return false;
        FastDomain& domain = domains[it->second];
        if (constraint.width != domain.varp->width() || constraint.viewWidth <= 0
            || constraint.viewLsb < 0
            || constraint.viewLsb > constraint.width - constraint.viewWidth)
            return false;
        domain.covered = true;
        if (constraint.isEnum) {
            if (constraint.viewLsb || constraint.viewWidth != constraint.width) return false;
            enumNeeded.erase(constraint.datap);
        }
        if (fastPinned(constraint)) {
            const QData mask = VL_MASK_Q(constraint.viewWidth) << constraint.viewLsb;
            QData bits = constraint.ranges[0].lo;
            if (constraint.isSigned) bits ^= QData{1} << (constraint.viewWidth - 1);
            bits = (bits << constraint.viewLsb) & mask;
            domain.pinConflict |= ((domain.pinBits ^ bits) & domain.pinMask & mask) != 0;
            domain.pinBits = (domain.pinBits & ~mask) | bits;
            domain.pinMask |= mask;
            continue;
        }
        if (domain.viewWidth
            && (domain.viewLsb != constraint.viewLsb || domain.viewWidth != constraint.viewWidth
                || domain.isSigned != constraint.isSigned))
            return false;
        domain.viewLsb = constraint.viewLsb;
        domain.viewWidth = constraint.viewWidth;
        domain.isSigned = constraint.isSigned;
    }
    if (!enumNeeded.empty()) return false;
    for (FastDomain& domain : domains) {
        if (!domain.covered || !fastView(domain)) return false;
    }
    for (const FastConstraint& constraint : m_fastConstraints) {
        if (constraint.isSoft || fastPinned(constraint)) continue;
        FastDomain& domain = domains[indices[constraint.datap]];
        domain.ranges = fastIntersect(domain.ranges, fastUnion(constraint.ranges));
        if (constraint.isDist) {
            if (domain.distp) return false;  // Multiple retained distributions need the solver
            domain.distp = &constraint;
        }
    }
    return true;
}

int VlRandomizer::nextFast(VlRNG& rngr) {
    if (solverSamples() || m_fastDisabled || m_fastConstraints.empty() || m_vars.empty()
        || !m_randcVarNames.empty() || !m_uniqueArrays.empty() || !m_frozenPins.empty()
        || !m_solveBefore.empty() || m_funcRoundLast || hasFrozenVar()) {
        return -1;
    }
    std::vector<FastDomain> domains;
    std::unordered_map<void*, size_t> indices;
    if (!fastDomains(domains, indices)) return -1;
    for (const FastDomain& domain : domains) {
        if (domain.ranges.empty()) {
            // Default-on diagnostics retain the existing solver/source-core path.
            return Verilated::threadContextp()->warnUnsatConstr() ? -1 : 0;
        }
    }
    // IEEE 1800-2023 18.5.13: keep each soft iff it is compatible with the
    // hard domain and the higher-priority softs already retained.
    for (auto it = m_fastConstraints.rbegin(); it != m_fastConstraints.rend(); ++it) {
        if (!it->isSoft) continue;
        FastDomain& domain = domains[indices[it->datap]];
        FastRanges intersection = fastIntersect(domain.ranges, fastUnion(it->ranges));
        if (intersection.empty()) continue;
        domain.ranges = std::move(intersection);
        if (it->isDist) {
            if (domain.distp) return -1;
            domain.distp = &*it;
        }
    }
    const size_t freeDomains
        = std::count_if(domains.begin(), domains.end(), [](const FastDomain& d) {
              return d.ranges.size() != 1 || d.ranges[0].lo != d.ranges[0].hi;
          });
    // Every original item is univariate and state-only. One free domain plus
    // independently proved singleton domains needs no coupled solver work.
    if (freeDomains > 1) return -1;
    // Prepare every value before committing any write. Overflow/unsupported sampling
    // falls back without advancing the caller's RNG or changing SV storage.
    VlRNG trialRng = rngr;
    std::vector<QData> values;
    for (const FastDomain& domain : domains) {
        QData value = domain.ranges[0].lo;
        const bool pinned = domain.ranges.size() == 1 && value == domain.ranges[0].hi;
        if (!pinned && !fastSample(trialRng, domain.ranges, domain.distp, value)) return -1;
        if (domain.isSigned) value ^= QData{1} << (domain.viewWidth - 1);
        const QData viewMask = VL_MASK_Q(domain.viewWidth) << domain.viewLsb;
        values.push_back((value << domain.viewLsb) | (domain.pinBits & ~viewMask));
    }
    for (size_t i = 0; i < domains.size(); ++i) {
        const VlRandomVar* const varp = domains[i].varp;
        if (varp->width() <= VL_BYTESIZE) {
            *static_cast<CData*>(varp->datap(0)) = values[i];
        } else if (varp->width() <= VL_SHORTSIZE) {
            *static_cast<SData*>(varp->datap(0)) = values[i];
        } else if (varp->width() <= VL_IDATASIZE) {
            *static_cast<IData*>(varp->datap(0)) = values[i];
        } else {
            *static_cast<QData*>(varp->datap(0)) = values[i];
        }
    }
    rngr = trialRng;
    return 1;
}

bool VlRandomizer::nextRandomize(VlRNGReseeds& rngr, bool checkOnly, const bool sizeSolve) {
    m_unsat = false;
    if (VL_UNLIKELY(failed())) {
        static bool s_warned = false;
        if (!m_failWarned && !s_warned) {
            s_warned = true;
            VL_WARN_MT(m_failFilename, m_failLinenum, "", m_failPending.c_str());
        }
        return false;
    }
    // Check-only, resize, frozen and function-round calls retain their original
    // protocols. nextFast separately verifies enum domains and excludes randc.
    // The original setup and callbacks have already run.
    if (!checkOnly && !sizeSolve && !m_sizeSolved) {
        const int fastResult = nextFast(rngr);
        if (fastResult >= 0) return fastResult != 0;
    }
    // No rand variables: randomize() still checks the constraints (IEEE 1800-2023 18.11.1)
    if (!checkOnly && m_vars.empty() && m_uniqueArrays.empty() && m_constraints.empty()) {
        return true;
    }
    if (checkOnly && m_vars.empty() && m_constraints.empty()) return true;
    VlSolverSession& sess = s_solverSession;
    const VerilatedLockGuard lock{sess.m_mutex};
    m_checkOnly = checkOnly;
    m_sizeSolve = sizeSolve;
    std::vector<std::string> uniqueExprs = buildUniqueExprs();
    // pin_frozen() constraints of the variables registered by now
    for (const auto& pin : m_frozenPins) {
        if (m_vars.count(pin.first)) uniqueExprs.push_back(pin.second);
    }
    addAliasExprs(uniqueExprs);
    // The sizes the elements could not be solved with
    if (sizeSolve) {
        uniqueExprs.insert(uniqueExprs.end(), m_sizeExclusions.begin(), m_sizeExclusions.end());
    }

    // Randc exclusion-based cycling: exclude previously used values per randc var.
    // When solver returns unsat (all values exhausted), clear history for new cycle.
    // An earlier function-call solve round has fewer constraints, not changed ones
    if (!m_randcVarNames.empty() && !funcPreRound()) {
        const size_t currentHash = hashConstraints(uniqueExprs, true);
        // The final solve continues the history its size solve checked, though the resize
        // changes the hash
        const bool sizeSolved = std::exchange(m_sizeSolved, false);
        // Invalidate history if constraints changed (e.g., constraint_mode toggled)
        if (currentHash != m_randcConstraintHash && !sizeSolved) m_randcUsedValues.clear();
        m_randcConstraintHash = currentHash;
    }

    // Reseeded from outside, so everything cached came from the old seed.
    if (m_ug2.rngReseeds != rngr.reseeds()) {
        m_ug2 = Unigen2State{};
        m_phaseSampleStats.clear();
    }

    // Fix the function arguments solved in earlier rounds (IEEE 1800-2023 18.5.11)
    for (const FuncArgRound& argRound : m_funcArgRounds) {
        if (argRound.round < m_funcRound && !argRound.pin.empty()) {
            m_constraints.push_back(argRound.pin);
            m_constraintVarEnds.push_back(m_constraintVarNames.size());  // Names no randc
            m_constraintTablesHash.push_back(0);
        }
    }

    // A frozen array the solver is given no text naming keeps its value, unregistered: the
    // solver needs no array logic or values for it (IEEE 1800-2023 18.8)
    std::map<std::string, std::shared_ptr<const VlRandomVar>> hidden;
    hideUnnamedFrozen(hidden);

    // Pinned vars make phase ordering moot; skip phased path in check-only.
    bool result;
    m_spreadFailed = false;
    sess.beginCall();
    if (!m_checkOnly && !m_solveBefore.empty()) {
        result = nextPhased(rngr, sess, uniqueExprs);
    } else {
        result = nextFlat(rngr, sess, uniqueExprs);
    }
    m_vars.insert(hidden.begin(), hidden.end());
    // The solution found before the spreading failed satisfies the constraints, so it is
    // returned (IEEE 1800-2023 18.6.3), though less random
    const std::string heldReply = sess.takeHeldReply();
    if (!result && !heldReply.empty()) warnSolverReply(heldReply);
    if (result && (m_spreadFailed || !heldReply.empty()) && !m_warnedSpreadFailed) {
        m_warnedSpreadFailed = true;
        VL_WARN_MT(__FILE__, __LINE__, "randomize",
                   "Solver failed while spreading the solution, so this randomize() returned "
                   "it less random; warned once per object.");
    }
    sess.endCall(result);
    m_ug2.rngReseeds = rngr.reseeds();
    m_checkOnly = false;
    m_sizeSolve = false;
    m_sizeSolved = sizeSolve && result;
    return result;
}

void VlRandomizer::addAliasExprs(std::vector<std::string>& exprsr) const {
    // A variable or array registered under several names, as through two handles to one
    // object, has one value
    std::unordered_map<const void*, const std::string*> namesByData;
    for (const auto& pair : m_vars) {
        // The storage of a variable, or of the first element an array holds now
        const void* datap = nullptr;
        if (pair.second->dimension()) {
            const auto elemIt = m_arr_vars.find({pair.first, 0});
            if (elemIt == m_arr_vars.end()) continue;
            datap = elemIt->second->m_datap;
        } else {
            datap = pair.second->datap(0);
        }
        const auto it = namesByData.emplace(datap, &pair.first);
        if (!it.second) exprsr.push_back(aliasExpr(*it.first->second, pair.first));
    }
}

std::string VlRandomizer::aliasExpr(const std::string& name, const std::string& otherName) {
    return "(__Vbv (= " + name + " " + otherName + "))";
}

std::vector<std::string> VlRandomizer::buildUniqueExprs() const {
    std::vector<std::string> exprs;
    if (m_uniqueArrays.empty()) return exprs;
    const auto arrVarsp = std::make_shared<const ArrayInfoMap>(m_arr_vars);
    for (const auto& keyArrNames : m_uniqueArrays) {
        uint32_t matchingElementsCount = 0;
        std::ostringstream varsString;

        for (const auto& baseName : keyArrNames.second) {
            const auto it = m_vars.find(baseName);
            if (it == m_vars.end()) continue;
            const VlRandomVar& var = *it->second;
            // Select the elements the array actually holds now, by their own index
            // or key, rather than by ordinal position
            var.setArrayInfo(arrVarsp);
            // 'distinct' needs at least two operands; fewer elements are trivially unique
            matchingElementsCount += var.countMatchingElements(*arrVarsp, baseName);
            var.emitGetValue(varsString);
        }

        if (matchingElementsCount < 2) continue;
        std::ostringstream os;
        os << "(__Vbv (distinct " << varsString.str() << "))";
        exprs.push_back(os.str());
    }
    return exprs;
}

// Seed the solver from the object's generator, so a solver-sampled result still
// follows +verilator+seed and the object's random stability.
static void emitSolverSeed(std::ostream& os, VlRNG& rngr) {
    os << "(set-option :random-seed " << (VL_RANDOM_RNG_I(rngr) & 0x7fffffffU) << ")\n";
}

// The runtime's own symbols (these, the __Va<N> and __Vd<N> literals and the __Vcons<N>
// labels) use the __V prefix Verilator reserves, so no random variable shares them
void VlRandomizer::emitDefines(std::ostream& os) const {
    os << "(define-fun __Vbv ((b Bool)) (_ BitVec 1) (ite b #b1 #b0))\n";
    os << "(define-fun __Vbool ((v (_ BitVec 1))) Bool (= #b1 v))\n";
}

void VlRandomizer::emitDeclares(std::ostream& os, bool pinCurrent) const {
    for (const std::string& name : m_freshVars) {
        os << "(declare-fun " << name << " () (_ BitVec 32))\n";
    }
    m_scalarElems.clear();
    for (const auto& ghost : m_ghostElems) {
        os << "(declare-fun " << ghost.first << " () (_ BitVec " << ghost.second.m_width << "))\n";
    }
    for (const auto& var : m_vars) {
        if (var.second->dimension() > 0) {
            auto arrVarsp = std::make_shared<const ArrayInfoMap>(m_arr_vars);
            var.second->setArrayInfo(arrVarsp);
        }
        if (var.second->scalar()) {
            // Element by element, see elemTerm
            for (int j = 0;; ++j) {
                const auto it = m_arr_vars.find({var.first, j});
                if (it == m_arr_vars.end()) break;
                const std::string& name = var.second->elementName(it->second->m_indices[0]);
                os << "(declare-fun " << name << " () (_ BitVec " << var.second->width() << "))\n";
                m_scalarElems[name] = std::make_pair(var.second.get(), it->second);
            }
        } else {
            os << "(declare-fun " << var.first << " () ";
            var.second->emitType(os);
            os << ")\n";
        }
        // Pin each var, or each array element, to its current value
        if (pinCurrent) {
            const int elements
                = var.second->dimension() ? var.second->totalWidth() / var.second->width() : 1;
            for (int j = 0; j < elements; ++j) {
                os << "(assert (=";
                var.second->emitElement(os, j);
                os << ' ';
                var.second->emitConcreteValue(os, j);
                os << "))\n";
            }
        }
        const auto domainIt = m_enumDomains.find(var.first);
        if (domainIt == m_enumDomains.end()) continue;
        for (int j = 0; j < var.second->totalWidth() / var.second->width(); ++j) {
            os << "(assert (let ((__Ve";
            var.second->emitElement(os, j);
            os << ")) " << domainIt->second << "))\n";
        }
    }
    emitChainDefines(os);
    // Variables registered by different paths to the same object, as through two handles to it,
    // are one variable
    std::map<const void*, const VlRandomVar*> scalars;
    for (const auto& var : m_vars) {
        if (var.second->dimension()) continue;
        const auto pair = scalars.emplace(var.second->datap(0), var.second.get());
        if (!pair.second) {
            os << "(assert (= " << pair.first->second->name() << ' ' << var.first << "))\n";
        }
    }
    // After the variables, which a table may read
    for (size_t j = 0; j < m_tables.size(); ++j) {
        os << "(define-fun " << m_tableNames[j] << ' ' << m_tableHeads[j] << m_tables[j] << ")\n";
    }
}

void VlRandomizer::table_begin(int indexWidth, int valueWidth, bool positional, uint8_t needs) {
    m_tableBuilders.push_back(TableBuilder{"((?i (_ BitVec " + std::to_string(indexWidth)
                                               + "))) (_ BitVec " + std::to_string(valueWidth)
                                               + ") ",
                                           indexWidth,
                                           positional,
                                           needs,
                                           {},
                                           {}});
}

void VlRandomizer::table_entry(const std::string& key, std::string value) {
    m_tableBuilders.back().keys.push_back(key);
    m_tableBuilders.back().values.push_back(std::move(value));
}

// Append to 'body' a test of the bits of '?i' from 'bit' down, choosing among the values at
// positions 'lo' and above
static void appendBitTests(std::string& body, const std::vector<std::string>& values, size_t lo,
                           int bit) {
    while (bit >= 0 && lo + (size_t{1} << bit) >= values.size()) --bit;  // No upper half
    if (bit < 0) {
        body += values[lo];
        return;
    }
    body += "(ite (= ((_ extract " + std::to_string(bit) + ' ' + std::to_string(bit)
            + ") ?i) #b1) ";
    appendBitTests(body, values, lo + (size_t{1} << bit), bit - 1);
    body += ' ';
    appendBitTests(body, values, lo, bit - 1);
    body += ')';
}
// Append the body of a table to 'body', linear in the number of keys. Keys that are the
// 'positional' 0, 1, ... are found by a test of each bit of the index of 'indexWidth' bits, which
// a solve splits on faster than on a test of each key, '(ite (= ?i k) v ...)', as other keys are.
static void appendTableBody(std::string& body, const std::vector<std::string>& keys,
                            const std::vector<std::string>& values, bool positional,
                            int indexWidth, const std::string& otherwise) {
    if (positional && !values.empty()) {
        // The positions fit the index, which the compiler makes at least 32 bits wide
        assert(indexWidth >= 64 || values.size() < (uint64_t{1} << indexWidth));
        int bits = 0;
        while ((size_t{1} << bits) < values.size()) ++bits;
        body += "(ite (bvult ?i (_ bv" + std::to_string(values.size()) + ' '
                + std::to_string(indexWidth) + ")) ";
        appendBitTests(body, values, 0, bits - 1);
        body += ' ' + otherwise + ')';
        return;
    }
    for (size_t j = 0; j < keys.size(); ++j) {
        body += "(ite (= ?i " + keys[j] + ") " + values[j] + ' ';
    }
    body += otherwise;
    body.append(keys.size(), ')');
}

std::string VlRandomizer::table_end(const std::string& otherwise) {
    TableBuilder builder = std::move(m_tableBuilders.back());
    m_tableBuilders.pop_back();
    std::string body;
    appendTableBody(body, builder.keys, builder.values, builder.positional, builder.indexWidth,
                    otherwise);
    size_t hash = std::hash<std::string>{}(builder.head);
    hash = hash * 31 + std::hash<std::string>{}(body);
    m_pendingTablesHash
        ^= hash + 0x9e3779b9 + (m_pendingTablesHash << 6) + (m_pendingTablesHash >> 2);
    const auto range = m_tableIds.equal_range(hash);
    for (auto it = range.first; it != range.second; ++it) {
        if (m_tables[it->second] == body && m_tableHeads[it->second] == builder.head) {
            return m_tableNames[it->second];
        }
    }
    m_tableIds.emplace(hash, m_tables.size());
    m_tableNames.push_back("__Vt" + std::to_string(m_tables.size()) + m_tablePrefix);
    m_tables.push_back(std::move(body));
    m_tableHeads.push_back(std::move(builder.head));
    m_tableNeeds.push_back(builder.needs);
    return m_tableNames.back();
}

void VlRandomizer::table_prefix_from(VlRandomizer& into) {
    m_tablePrefix = into.m_tablePrefix + '.' + std::to_string(into.m_tablesMerged++);
}

void VlRandomizer::emitAsserts(std::ostream& os, const std::vector<std::string>& extras,
                               bool named) const {
    int j = 0;
    for (const std::string& constraint : m_constraints) {
        if (named) {
            os << "(assert (! (= #b1 " << constraint << ") :named __Vcons" << j++ << "))\n";
        } else {
            os << "(assert (= #b1 " << constraint << "))\n";
        }
    }
    for (const std::string& extra : extras) {
        if (named) {
            os << "(assert (! (= #b1 " << extra << ") :named __Vcons" << j++ << "))\n";
        } else {
            os << "(assert (= #b1 " << extra << "))\n";
        }
    }
}

// Constant-array constructors are outside the restricted array/bit-vector logics.
static bool constraintsUseConstArray(const std::vector<std::string>& constraints) {
    for (const std::string& constraint : constraints) {
        if (constraint.find("(as const (Array ") != std::string::npos) return true;
    }
    return false;
}

void VlRandomizer::emitFlat(std::ostream& os, const std::vector<std::string>& uniqueExprs) const {
    os << "(set-logic " << solverLogic() << ")\n";
    emitDefines(os);
    emitDeclares(os, m_checkOnly);
    emitAsserts(os, uniqueExprs, false);
    // randc exclusions vs. a pinned current value would make every check
    // trivially UNSAT after the first cycle.
    if (!m_checkOnly) emitRandcExclusions(os);
}

bool VlRandomizer::nextFlat(VlRNG& rngr, VlSolverSession& sess,
                            const std::vector<std::string>& uniqueExprs)
    VL_REQUIRES(sess.m_mutex) {
    if (!solverSamples() && m_randcVarNames.empty() && !m_checkOnly && !hasFrozenVar()
        && unigen2(rngr, sess, uniqueExprs)) {
        return true;
    }
    VlSolverTxn txn{sess};
    if (!txn.ok()) return false;
    std::iostream& os = sess.os();
    // Randc retry: if unsat due to randc exhaustion, clear history and retry once
    const bool hasRandc = !m_randcVarNames.empty();
    decltype(m_randcUsedValues) usedValues;  // The history cleared for the retry
    for (int attempt = 0; attempt < (hasRandc ? 2 : 1); ++attempt) {
        os << "(set-option :produce-models true)\n";
        if (!solverSamples()) {
            // Lets the diversity pins learn which assumptions conflict.
            os << "(set-option :produce-unsat-assumptions true)\n";
        } else if (!m_checkOnly) {
            // Check-only results are not random, so leave the random state alone
            emitSolverSeed(os, rngr);
        }
        emitFlat(os, uniqueExprs);
        if (relaxSoftConstraints(sess) != VlSolverStatus::SAT) return false;
        os << "(check-sat)\n";
        const VlSolverStatus status = sess.readStatus();

        if (status != VlSolverStatus::SAT) {
            if (status != VlSolverStatus::UNSAT) return false;
            os << "(reset)\n";
            // If randc vars have used values, this may be cycle exhaustion - retry
            if (hasRandc && !m_randcUsedValues.empty() && attempt == 0) {
                usedValues.swap(m_randcUsedValues);
                continue;  // Retry without exclusions
            }
            // A failed call does not change the randc cycles (IEEE 1800-2023 18.6.3)
            if (attempt) m_randcUsedValues.swap(usedValues);
            // Skip the unsat-core path in check-only: it re-declares vars
            // without pinning, so the solver's free assignment would clobber
            // user state.
            if (m_checkOnly) return false;
            // Genuine unsat: report via unsat-core, unless the call tries other sizes
            m_unsat = true;
            if (!m_quietUnsat) reportUnsatSetup(sess, uniqueExprs);
            return false;
        }
        if (!applyModel(sess)) return false;

        if (!m_checkOnly) {
            if (!solverSamples()) {
                sess.holdReplies(true);
                solveDiversity(rngr, sess, nullptr, &uniqueExprs);
                sess.holdReplies(false);
                m_spreadFailed |= sess.failed();
            }
            // Check-only must not advance randc cycle state.
            recordRandcValues();
        }
        return true;
    }
    return false;  // Should not reach here
}

static constexpr uint64_t ug2MaxBits = 1024;  // Most solver variable bits to sample with UniGen2

// Enumerate one cell of the solution space, and cache the solutions in m_ug2.loThreshWitnesses.
// The next call with the same constraint set will drain the cache before running the full
// mechanism again.
bool VlRandomizer::unigen2(VlRNG& rngr, VlSolverSession& sess,
                           const std::vector<std::string>& uniqueExprs) VL_REQUIRES(sess.m_mutex) {
    if (!m_softConstraints.empty()) return false;
    // Its XORs span every bit, which gets slow to solve (about a minute per call at 16k
    // bits) while the large-space cells it can afford are poorly spread, so wide problems
    // use the flat path
    uint64_t bits = 0;
    for (const auto& var : m_vars) {
        const uint64_t elements = var.second->dimension()
                                      ? var.second->countMatchingElements(m_arr_vars, var.first)
                                      : 1;
        bits += elements * var.second->width();
    }
    if (bits > ug2MaxBits) return false;

    const size_t currentHash = hashConstraints(uniqueExprs);
    // Params and batch are computed for specific constraint set, so drop them
    // once it changes.
    if (m_ug2.paramHash != currentHash) {
        m_ug2.loThreshWitnesses.clear();
        m_ug2.paramsValid = false;
        m_ug2.isLargeSpace = false;
        m_ug2.paramHash = currentHash;
        // First sighting of this constraint set.
        // Decline now and let the next call with the same set run UG2.
        return false;
    }
    // With no element to enumerate there is nothing to sample, and bsat() would send an empty
    // (get-value ()); the plain solve still checks the constraints. Asks this call's array table,
    // as the variables' own array info and counts may still describe an earlier call.
    if (std::none_of(m_vars.begin(), m_vars.end(), [this](const auto& var) {
            return var.second->dimension() == 0
                   || var.second->hasMatchingElements(m_arr_vars, var.second->name());
        })) {
        return false;
    }

    // Nothing cached from a previous UG2 run, so refill the batch first.
    if (m_ug2.loThreshWitnesses.empty()) {
        VlSolverTxn txn{sess};
        if (!txn.ok()) return false;
        std::iostream& solver = sess.os();

        solver << "(set-option :produce-models true)\n";
        solver << "(set-logic " << solverLogic() << ")\n";
        emitDefines(solver);
        emitDeclares(solver, false);
        emitAsserts(solver, uniqueExprs, false);

        if (!m_ug2.paramsValid) {
            // Searches once per constraint set for how finely to cut the space, and
            // caches parameters
            if (!estimateParameters(sess, rngr)) return false;
            m_ug2.paramsValid = true;
            m_ug2.lastSuccessI = -1;  // new params, so the old hint no longer applies
        }

        // A failed enumeration, as after a solver error, falls back to the plain solve
        if (!generateSamples(sess, rngr)) return false;
    }

    // Cached or just refilled - there is a witness to write into the variables
    Witness witness = std::move(m_ug2.loThreshWitnesses.back());
    m_ug2.loThreshWitnesses.pop_back();
    writeBackWitness(witness);
    return true;
}

void VlRandomizer::writeBackWitness(const Witness& witness) {
    for (const auto& varEntry : witness) {
        if (m_sizeSolve && !m_sizeVars.count(varEntry.first)) continue;
        const auto& varp = m_vars.at(varEntry.first);
        keepRoundValues(*varp);
        for (const auto& elemEntry : varEntry.second) {
            if (varp->dimension() > 0) {
                // set() needs current array info, and a witness from the
                // cached batch skips the solver, so nothing else sets it.
                auto arrVarsp = std::make_shared<const ArrayInfoMap>(m_arr_vars);
                varp->setArrayInfo(arrVarsp);
                std::ostringstream idxStream;
                idxStream << "#x" << std::hex << std::setw(8) << std::setfill('0')
                          << elemEntry.first;
                varp->set(idxStream.str(), elemEntry.second);
            } else {
                varp->set("", elemEntry.second);
            }
        }
    }
}

// Ask for a solution, block it, ask again - so every answer is a new one.
int VlRandomizer::bsat(VlSolverSession& sess, size_t bound, std::vector<Witness>& witnesses,
                       VlRNG* diversifyRngp) VL_REQUIRES(sess.m_mutex) {
    std::iostream& solver = sess.os();
    witnesses.clear();
    witnesses.reserve(bound);
    // get-value responses preserve request order, so build the (var,
    // element) order once and read results back positionally.
    std::vector<std::pair<std::string, int>>& order = m_ug2.bsatOrder;
    order.clear();
    for (const auto& var : m_vars) {
        const int elementCount = var.second->totalWidth() / var.second->width();
        for (int j = 0; j < elementCount; ++j) order.emplace_back(var.first, j);
    }

    int assumeNum = 0;
    while (witnesses.size() < bound) {
        VlSolverStatus status = VlSolverStatus::FAIL;
        if (diversifyRngp && !witnesses.empty()) {
            // To increase the randomization, add an assumption for one var in one specific call
            const Witness& prev = witnesses.back();
            const std::pair<std::string, int>& pick
                = order[VL_RANDOM_RNG_I(*diversifyRngp) % order.size()];
            solver << "(declare-fun __Vd" << assumeNum << " () Bool)\n";
            solver << "(assert (= __Vd" << assumeNum << " (not (=";
            m_vars.at(pick.first)->emitElement(solver, pick.second);
            solver << ' ' << prev.at(pick.first).at(pick.second) << "))))\n";
            solver << "(check-sat-assuming (__Vd" << assumeNum << "))\n";
            ++assumeNum;
            status = sess.readStatus();
            // The solver may not support assumptions; get back in step for the plain check
            if (status == VlSolverStatus::FAIL) sess.resync();
        }
        if (status != VlSolverStatus::SAT) {
            solver << "(check-sat)\n";
            status = sess.readStatus();
        }
        if (status != VlSolverStatus::SAT) {
            // "unsat" is the cell running out; anything else is the solver giving up
            if (VL_UNLIKELY(status != VlSolverStatus::UNSAT)) return -1;
            break;
        }

        solver << "(get-value (";
        for (const auto& entry : order) m_vars.at(entry.first)->emitElement(solver, entry.second);
        solver << "))\n";

        // Read the whole balanced reply first, so a malformed one cannot desync the pipe
        std::string reply;
        if (VL_UNLIKELY(!sess.readSExpr(reply))) return -1;
        std::istringstream is{reply};
        char c = 0;
        is >> c;  // readSExpr only returns a reply that opens with '('
        Witness witness;
        for (const auto& entry : order) {
            if (VL_UNLIKELY(!(is >> c) || c != '(')) return -1;  // LCOV_EXCL_BR_LINE
            // The var's name, or an element's (select ...): positional, so not its indices
            std::vector<std::string> indices;
            if (VL_UNLIKELY(termVarName(readSMTTerm(is), indices) != entry.first)) return -1;
            std::string value = readSMTLastTerm(is);
            const int width = m_vars.at(entry.first)->width();
            smtIndexedToBinary(value, width);
            // The batch outlives this call, so reject a bad value before it is cached
            if (VL_UNLIKELY(!validSMTNum(value) || !smtValueOfWidth(value, width))) return -1;
            witness[entry.first][entry.second] = value;
        }  // LCOV_EXCL_BR_LINE
        if (VL_UNLIKELY(!(is >> c) || c != ')')) return -1;  // LCOV_EXCL_BR_LINE

        // Forbid this exact assignment so the next
        // (check-sat) is forced to find a genuinely different witness.
        // SMT-LIB 'and' takes at least two operands, so a lone equality stands alone
        const bool single = order.size() == 1;
        solver << (single ? "(assert (not" : "(assert (not (and");
        for (const auto& varEntry : witness) {
            for (const auto& elemEntry : varEntry.second) {
                solver << " (=";
                m_vars.at(varEntry.first)->emitElement(solver, elemEntry.first);
                solver << ' ' << elemEntry.second << ")";
            }
        }
        solver << (single ? "))\n" : ")))\n");
        witnesses.push_back(std::move(witness));
    }  // LCOV_EXCL_BR_LINE
    return static_cast<int>(witnesses.size());
}

// Each equation selects a random subset of bits by a coin-flip for each bit, and then sets the XOR
// of those bits to a random value.
void VlRandomizer::unigenXors(std::iostream& solver, VlRNG& rngr, int bits) {
    if (bits <= 0) return;  // 0 hash constraints == no extra assertion needed at all
    std::vector<bool> target(bits);
    for (int k = 0; k < bits; ++k) target[k] = VL_RANDOM_RNG_I(rngr) & 1;

    solver << "(assert ";
    solver << "(= #b";
    for (int k = 0; k < bits; ++k) solver << (target[k] ? '1' : '0');
    if (bits > 1) solver << " (concat";
    for (int k = 0; k < bits; ++k) {
        // Two #b0 seed the bvxor chain, so it has at least two operands (SMT-LIB 2.6)
        // even when this equation's coin flips select no bit; zeros cannot change an xor.
        solver << " (bvxor #b0 #b0";
        for (const auto& var : m_vars) {
            for (int j = 0; j < var.second->totalWidth(); ++j) {
                if (VL_RANDOM_RNG_I(rngr) & 1) var.second->emitExtract(solver, j);
            }
        }
        solver << ')';
    }
    if (bits > 1) solver << ')';
    solver << "))\n";
}

// --- UniGen2 constants ---
static constexpr double ug2Kappa = 0.638;  // Parameter controlling the tolerance of the uniformity
                                           // guarantee. Set at the paper's default value.
// Values used in the large space mode:
static constexpr int ug2HiThreshLargeSpace = 16;  // Num of solutions to enumerate
static constexpr int ug2BatchLargeSpace = 16;  // Num of solutions to cache
static constexpr int ug2HashBitsLargeSpace
    = 10;  // Num of XORs to add to the solver, also cap of the bsat() search

bool VlRandomizer::estimateParameters(VlSolverSession& sess, VlRNG& rngr)
    VL_REQUIRES(sess.m_mutex) {
    std::iostream& solver = sess.os();
    // Below formulas are taken from the UniGen2 paper, Sec. 4, Algorithm 1
    const double pivot = ceil(4.03 * pow((1 + 1 / ug2Kappa), 2));
    m_ug2.hiThresh = static_cast<int>(ceil(1 + sqrt(2) * (1 + ug2Kappa) * pivot));
    m_ug2.loThresh = static_cast<int>(floor(pivot / (sqrt(2) * (1 + ug2Kappa))));

    // A space so small can never reach loThresh, so enumerate it whole instead.
    // push/pop keeps bsat() blocking clauses out of that search.
    solver << "(push 1)\n";
    std::vector<Witness> tinyWitnesses;
    const int tinyCellSize = bsat(sess, 61, tinyWitnesses);
    solver << "(pop 1)\n";
    if (tinyCellSize < 0) return false;
    if (tinyCellSize >= 1 && tinyCellSize <= 60) {
        m_ug2.hashBits = 0;
        m_ug2.loThresh = tinyCellSize;  // batch = the whole enumerated set
        m_ug2.hiThresh = tinyCellSize + 1;
        return true;
    }

    int totalBits = 0;
    for (const auto& var : m_vars) totalBits += var.second->totalWidth();
    int solCount = 0;
    // Cap the search with ug2HashBitsLargeSpace: Larger spaces cannot be hashed in useful
    // time, so stop and just use fixed number of XORs. Limit set empirically from measured solve
    // times.
    const int iMax = totalBits < ug2HashBitsLargeSpace ? totalBits : ug2HashBitsLargeSpace;
    std::vector<Witness> witnesses;  // Reused across trials; bsat() clears it
    for (int i = 1; i <= iMax; ++i) {
        solver << "(push 1)\n";
        unigenXors(solver, rngr, i);
        const int bound = 61;
        solCount = bsat(sess, bound, witnesses);
        if (solCount < 0) {
            solver << "(pop 1)\n";
            return false;
        }
        if (solCount >= 1 && solCount < bound) {
            m_ug2.hashBits
                = static_cast<int>(round(log2(solCount) + i + log2(1.8)
                                         - log2(pivot)));  // formula taken from the Unigen2 paper
            solver << "(pop 1)\n";
            return true;
        }
        solver << "(pop 1)\n";
    }
    m_ug2.isLargeSpace = true;
    m_ug2.hashBits = ug2HashBitsLargeSpace;
    m_ug2.hiThresh = ug2HiThreshLargeSpace;
    return true;
}

bool VlRandomizer::generateSamples(VlSolverSession& sess, VlRNG& rngr) VL_REQUIRES(sess.m_mutex) {
    std::iostream& solver = sess.os();
    // Try whichever of hashBits number worked last call first
    // (UniGen2 Sec. 4, "leapfrogging" in spirit but without weakening guarantees).
    // On a large space no cell was ever enumerable, so just try most hash bits first for the
    // smallest cell.
    const int lowestCount = m_ug2.hashBits - 2;
    int candidates[3] = {lowestCount, lowestCount + 1, lowestCount + 2};
    if (m_ug2.isLargeSpace) {
        candidates[0] = m_ug2.hashBits;
        candidates[1] = m_ug2.hashBits - 1;
        candidates[2] = m_ug2.hashBits - 2;
    } else if (m_ug2.lastSuccessI >= 0) {
        std::swap(candidates[0], candidates[m_ug2.lastSuccessI - lowestCount]);
    }

    std::vector<Witness> witnesses;  // Reused across candidates; bsat() clears it
    for (int t = 0; t < 3; ++t) {
        const int i = candidates[t];
        if (i < 0) continue;  // hashBits below 2 leaves fewer than three counts to try

        solver << "(push 1)\n";
        unigenXors(solver, rngr, i);
        const int solCount
            = bsat(sess, m_ug2.hiThresh, witnesses, m_ug2.isLargeSpace ? &rngr : nullptr);
        if (m_ug2.loThresh <= solCount && (solCount < m_ug2.hiThresh || m_ug2.isLargeSpace)) {
            m_ug2.lastSuccessI = i;
            const int take
                = m_ug2.isLargeSpace ? std::min(ug2BatchLargeSpace, solCount) : m_ug2.loThresh;
            // Pick them at random rather than the first ones enumerated -
            // partial Fisher-Yates, so the picks stay distinct.
            m_ug2.loThreshWitnesses.clear();
            std::vector<int> indices(witnesses.size());
            for (size_t k = 0; k < indices.size(); ++k) indices[k] = static_cast<int>(k);
            for (int k = 0; k < take; ++k) {
                const size_t pick
                    = static_cast<size_t>(k) + (VL_RANDOM_RNG_I(rngr) % (indices.size() - k));
                std::swap(indices[k], indices[pick]);
                m_ug2.loThreshWitnesses.push_back(std::move(witnesses[indices[k]]));
            }
            solver << "(pop 1)\n";
            return true;
        }
        solver << "(pop 1)\n";
    }
    m_ug2.lastSuccessI = -1;
    return false;
}

void VlRandomizer::solveDiversity(VlRNG& rngr, VlSolverSession& sess,
                                  const std::set<std::string>* fixedp,
                                  const std::vector<std::string>* uniqueExprsp)
    VL_REQUIRES(sess.m_mutex) {
    // Each variable and array element, but those in fixedp, already pinned
    std::vector<PinTerm> terms;
    for (const auto& var : m_vars) {
        if (fixedp && fixedp->count(var.first)) continue;
        // Nor one with rand_mode off, which keeps its value (IEEE 1800-2023 18.8)
        if (isFrozenVar(var.first, *var.second)) continue;
        // The solve of the array sizes keeps only the sizes, and spreads no element: those it
        // holds are of the old sizes, which the final solve picks again. It spreads the other
        // variables, though not kept, so a size equal to one takes its range (fastTargets).
        if (m_sizeSolve && var.second->dimension()) continue;
        const int width = var.second->width();
        for (int j = 0; j < var.second->totalWidth() / width; ++j) {
            terms.push_back({var.second.get(), j, 0, width, static_cast<int>(terms.size())});
        }
    }
    if (spreadTerms(rngr, sess, std::move(terms), uniqueExprsp) && !applyModel(sess)) {
        m_spreadFailed = true;
    }
}

// Into targetsr, each scalar's values by its range constraints, as nextFast reads them, where
// they narrow it: those of its whole width, but soft ones, which may be dropped, and dist
// ones, whose weights a uniform value would not follow. Variables with rand_mode off are not
// spread anyway.
void VlRandomizer::fastTargets(std::unordered_map<const void*, FastTarget>& targetsr) const {
    for (const FastConstraint& constraint : m_fastConstraints) {
        if (constraint.isSoft || constraint.isDist || constraint.viewLsb
            || constraint.viewWidth != constraint.width) {
            continue;
        }
        const auto it = targetsr.find(constraint.datap);
        if (it == targetsr.end()) {
            targetsr.emplace(constraint.datap,
                             FastTarget{fastUnion(constraint.ranges), constraint.width,
                                        constraint.isSigned, 0});
        } else if (it->second.isSigned == constraint.isSigned) {
            // The views of the whole of one variable have its signedness (see fastDomains)
            it->second.ranges = fastIntersect(it->second.ranges, fastUnion(constraint.ranges));
        }
    }
    for (auto it = targetsr.begin(); it != targetsr.end();) {
        FastTarget& target = it->second;
        bool narrows = !target.ranges.empty();
        for (const FastRange& range : target.ranges) {
            const QData size = range.hi - range.lo + 1;  // 0 for all 2^64 values
            narrows = narrows && size && target.count + size > target.count;
            target.count += size;
        }
        if (target.width < 64) narrows = narrows && target.count < (QData{1} << target.width);
        it = narrows ? std::next(it) : targetsr.erase(it);
    }
}

// A uniformly random value of target's ranges, decoded from their ordered coordinates: the
// ranges, from fastUnion and fastIntersect, are sorted and disjoint, so a uniform rank among
// their values names one value
QData VlRandomizer::fastTargetValue(VlRNG& rngr, const FastTarget& target) {
    QData pick = vl_fastBelow(rngr, target.count);
    QData value = 0;
    for (const FastRange& range : target.ranges) {
        if (pick <= range.hi - range.lo) {
            value = range.lo + pick;
            break;
        }
        pick -= range.hi - range.lo + 1;
    }
    return target.isSigned ? value ^ (QData{1} << (target.width - 1)) : value;
}

bool VlRandomizer::spreadTerms(VlRNG& rngr, VlSolverSession& sess, std::vector<PinTerm> terms,
                               const std::vector<std::string>* uniqueExprsp)
    VL_REQUIRES(sess.m_mutex) {
    // Tie each term, a variable, array element or part of one, to a random value via an
    // assumption literal and drop the literals that conflict with the constraints. Dropped
    // terms that can still change are split in halves that are tied again, down to single
    // bits, so free bits come out uniform and the surviving literals steer constrained ones
    // (value < N, #7563). A term that cannot (equal to another variable, or a solved size)
    // costs a check or two rather than one per bit, and wide data needs no per-bit literal
    // or XOR constraint.
    // The solver checks are bounded. When several wide parts of an element conflict and
    // the first one cannot change while the others keep their values, the element is
    // left as it is: it is likely one of a few constants, which random parts never fit,
    // so splitting would cost a check per part down to single bits. Past
    // diversityMaxChecks checks the literals kept so far are the result.
    // A random sample of the terms, past diversityMaxTerms
    if (terms.size() > diversityMaxTerms) {
        for (size_t i = 0; i < diversityMaxTerms; ++i) {
            std::swap(terms[i], terms[i + VL_RANDOM_RNG_I(rngr) % (terms.size() - i)]);
        }
        terms.resize(diversityMaxTerms);
    }
    std::iostream& os = sess.os();
    const auto emitTerm = [&](const PinTerm& term) {
        const bool whole = term.width == term.varp->width();
        if (!whole) os << " ((_ extract " << term.lsb + term.width - 1 << ' ' << term.lsb << ')';
        term.varp->emitElement(os, term.elem);
        if (!whole) os << ')';
    };
    // Checks spreading more terms (variables and array elements, not bits) take more work,
    // about the square of their number
    const uint64_t nterms = std::min<uint64_t>(terms.size(), 65536);
    const uint64_t checkLimit = std::min(
        diversityCheckLimitMax, diversityCheckLimit + diversityCheckLimitSquare * nterms * nterms);
    const VlSolverLimit limit{sess, checkLimit};
    std::string keep;  // Surviving literals
    int lits = 0;  // Literals declared so far
    int checksLeft = diversityMaxChecks;
    // Satisfied checks are the slow ones on large problems; past their limit, no further
    // check is made and the literals kept so far are the result
    int satisfiedLeft = diversityMaxSatisfied;
    const auto satisfied = [&]() {
        if (--satisfiedLeft <= 0) checksLeft = 0;
    };
    bool settled = true;  // The last check was satisfied, so its model satisfies keep
    std::vector<bool> dropped;
    // A whole scalar is tied first to a value its range constraints allow, if they narrow it
    std::unordered_map<const void*, FastTarget> targets;
    fastTargets(targets);
    while (!terms.empty() && checksLeft > 0) {
        for (size_t k = 0; k < terms.size(); ++k) {
            PinTerm& term = terms[k];
            os << "(declare-fun __Va" << lits + k << " () Bool)\n";
            os << "(assert (= __Va" << lits + k << " (=";
            emitTerm(term);
            os << " #b";
            const auto targetIt = term.lsb || term.varp->dimension()
                                      ? targets.end()
                                      : targets.find(term.varp->datap(0));
            if (targetIt != targets.end() && targetIt->second.width == term.width) {
                const QData value = fastTargetValue(rngr, targetIt->second);
                for (int b = term.width - 1; b >= 0; --b) os << ((value >> b) & 1 ? '1' : '0');
                term.value0 = (value >> (term.width - 1)) & 1;
            } else {
                IData bits = 0;
                for (int b = 0; b < term.width; ++b) {
                    if (!(b & VL_SIZEBITS_I)) bits = VL_RANDOM_RNG_I(rngr);
                    os << (VL_BITISSET_I(bits, b & VL_SIZEBITS_I) ? '1' : '0');
                }
                term.value0 = VL_BITISSET_I(bits, (term.width - 1) & VL_SIZEBITS_I) ? 1 : 0;
            }
            os << ")))\n";
        }
        std::vector<int> slotIds;
        settled = assumeDropping(rngr, sess, keep, lits, terms, dropped, checksLeft, nullptr,
                                 &slotIds, &satisfiedLeft);
        if (!settled) break;
        satisfied();
        std::vector<PinTerm> conflicted;
        std::vector<std::vector<PinTerm>> slots;  // Parts dropped for a whole array, per part
        for (size_t k = 0; k < terms.size(); ++k) {
            const PinTerm& term = terms[k];
            if (!dropped[k]) {
                keep += " __Va" + std::to_string(lits + k);
            } else if (term.width > 1 && slotIds[k] >= 0) {
                if (slots.size() <= static_cast<size_t>(slotIds[k])) slots.resize(slotIds[k] + 1);
                slots[slotIds[k]].push_back(term);
            } else if (term.width > 1) {
                conflicted.push_back(term);
            }
        }
        lits += terms.size();
        terms.clear();
        // Of a part dropped for a whole array, only a few elements spread over it are
        // checked below, and the others follow them: checking all would need a model
        // changing all of them, which is slow on a large array
        const size_t nalone = conflicted.size();
        std::vector<size_t> nsamples;  // Per slot
        for (const std::vector<PinTerm>& members : slots) {
            nsamples.push_back(std::min<size_t>(diversitySlotSamples, members.size()));
            for (size_t i = 0; i < nsamples.back(); ++i) {
                conflicted.push_back(members[diversitySample(i, members.size())]);
            }
        }
        // Out of checks, the last model, which satisfies keep, is the result
        if (conflicted.empty() || checksLeft <= 0) break;
        // Which conflicted terms can differ from the last model's values at all
        os << "(get-value (";
        for (const PinTerm& term : conflicted) emitTerm(term);
        os << "))\n";
        std::vector<std::string> values;
        if (!readValues(sess, conflicted, values)) {
            m_spreadFailed = true;
            return false;
        }
        for (size_t k = 0; k < conflicted.size(); ++k) {
            os << "(declare-fun __Va" << lits + k << " () Bool)\n";
            os << "(assert (= __Va" << lits + k << " (not (=";
            emitTerm(conflicted[k]);
            os << ' ' << values[k] << "))))\n";
        }
        std::vector<bool> guessed;
        settled
            = assumeDropping(rngr, sess, keep, lits, conflicted, dropped, checksLeft, &guessed);
        if (!settled) break;
        satisfied();
        // A term dropped as a guess may still change on its own, which would leave its
        // bits unspread, so check it alone
        for (size_t k = 0; k < conflicted.size() && checksLeft > 0; ++k) {
            if (!guessed[k]) continue;
            os << "(check-sat-assuming (" << keep << " __Va" << lits + k << "))\n";
            --checksLeft;
            const VlSolverStatus status = sess.readStatus();
            settled = status == VlSolverStatus::SAT;
            if (settled) {
                dropped[k] = false;
                satisfied();
            }
            if (!settled && status != VlSolverStatus::UNSAT) {
                checksLeft = 0;  // Cut short or failed: no further check
                break;
            }
        }
        lits += conflicted.size();
        std::map<int, std::vector<size_t>> changeable;  // Parts able to change, per element
        for (size_t k = 0; k < conflicted.size(); ++k) {
            if (!dropped[k]) changeable[conflicted[k].root].push_back(k);
        }
        std::set<int> stopped;  // Elements that are one of a few constants
        for (const auto& it : changeable) {
            const std::vector<size_t>& parts = it.second;
            if (checksLeft <= 0) break;
            if (conflicted[parts[0]].width <= diversityWideBits || parts.size() < 2) continue;
            std::string assumed = keep;
            for (size_t i = 0; i < parts.size(); ++i, ++lits) {
                os << "(declare-fun __Va" << lits << " () Bool)\n";
                os << "(assert (= __Va" << lits << (i ? " (=" : " (not (=");
                emitTerm(conflicted[parts[i]]);
                os << ' ' << values[parts[i]] << (i ? ")))\n" : "))))\n");
                assumed += " __Va" + std::to_string(lits);
            }
            os << "(check-sat-assuming (" << assumed << "))\n";
            --checksLeft;
            const VlSolverStatus status = sess.readStatus();
            settled = status == VlSolverStatus::SAT;
            if (settled) {
                satisfied();
            } else if (status == VlSolverStatus::UNSAT) {
                stopped.insert(it.first);
            } else {
                checksLeft = 0;  // Cut short or failed: no further check
                break;
            }
        }
        const auto split = [&](const PinTerm& term) {
            const int step = (term.width + 1) / 2;
            for (int lsb = 0; lsb < term.width; lsb += step) {
                const int width = std::min(step, term.width - lsb);
                terms.push_back({term.varp, term.elem, term.lsb + lsb, width, term.root});
            }
        };
        const auto splitting
            = [&](size_t k) { return !dropped[k] && !stopped.count(conflicted[k].root); };
        for (size_t k = 0; k < nalone; ++k) {
            if (splitting(k)) split(conflicted[k]);
        }
        size_t samplek = nalone;
        for (size_t sloti = 0; sloti < slots.size(); ++sloti) {
            bool any = false;
            for (size_t i = 0; i < nsamples[sloti]; ++i) any |= splitting(samplek++);
            if (!any) continue;
            for (const PinTerm& term : slots[sloti]) split(term);
        }
    }
    if (!settled) {
        // Out of checks, or a check failed or was cut short. With none kept, that is solving
        // the constraints again, which can cost many times the first check: after
        // assumptions, a solver such as z3 checks incrementally. Past the spreading limit,
        // a fresh session finds it again instead. Softs are kept only in this session.
        if (keep.empty() && uniqueExprsp && m_softConstraints.empty()) {
            os << "(check-sat-assuming ())\n";
            const VlSolverStatus status = sess.readStatus();
            if (status != VlSolverStatus::UNKNOWN) return status == VlSolverStatus::SAT;
            sess.limitChecks(0);
            // Which writes its model
            resolveFresh(rngr, sess, *uniqueExprsp,
                         std::min(diversityCheckLimitMax, diversityFreshLimit * checkLimit));
            return false;
        }
        // The kept literals have a solution, so finding it again is not limited.
        sess.limitChecks(0);
        os << "(check-sat-assuming (" << keep << "))\n";
        return sess.readStatus() == VlSolverStatus::SAT;
    }
    return true;
}

void VlRandomizer::resolveFresh(VlRNG& rngr, VlSolverSession& sess,
                                const std::vector<std::string>& uniqueExprs, uint64_t limit)
    VL_REQUIRES(sess.m_mutex) {
    std::iostream& os = sess.os();
    // Random hashes of the variables' bits make the solution a random one, as spreading
    // would have, at about the cost of the first check
    os << "(reset)\n";
    os << "(set-option :produce-models true)\n";
    emitFlat(os, uniqueExprs);
    for (int i = 0; i < diversityFreshHashes; ++i) {
        os << "(assert ";
        randomConstraint(os, rngr, 1);
        os << ")\n";
    }
    const VlSolverStatus status = [&]() VL_REQUIRES(sess.m_mutex) {
        const VlSolverLimit limited{sess, limit};
        os << "(check-sat)\n";
        return sess.readStatus();
    }();
    if (status == VlSolverStatus::SAT) {
        m_spreadFailed |= !applyModel(sess);
        return;
    }
    // Hashed out, cut short or failed: solve without them as before, at the incremental cost
    os << "(reset)\n";
    os << "(set-option :produce-models true)\n";
    emitFlat(os, uniqueExprs);
    os << "(check-sat-assuming ())\n";
    if (sess.readStatus() == VlSolverStatus::SAT) applyModel(sess);
}

bool VlRandomizer::assumeDropping(VlRNG& rngr, VlSolverSession& sess, const std::string& keep,
                                  int first, const std::vector<PinTerm>& terms,
                                  std::vector<bool>& droppedr, int& checksLeftr,
                                  std::vector<bool>* guessedp, std::vector<int>* slotIdsp,
                                  int* satisfiedLeftp) VL_REQUIRES(sess.m_mutex) {
    std::iostream& os = sess.os();
    droppedr.assign(terms.size(), false);
    if (guessedp) guessedp->assign(terms.size(), false);
    if (slotIdsp) slotIdsp->assign(terms.size(), -1);
    int nslots = 0;
    // Conflicts per part of an array's elements (and pinned value, for a single bit), and
    // whether each of them was among others in its unsat core
    std::map<std::tuple<const VlRandomVar*, int, int, int>, std::pair<int, bool>> slotConflicts;
    // How many more elements may conflict one by one, for parts whose samples all fit: a
    // share of the checks left and a few of the elements, as a constraint that rules out
    // many values (say d[i] < 200) would spend every check so
    std::map<std::tuple<const VlRandomVar*, int, int, int>, int> oneByOneLeft;
    // Into corer, the terms of an unsat core that are not dropped yet
    const auto coreTerms = [&](std::vector<int>& corer) VL_REQUIRES(sess.m_mutex) {
        corer.clear();
        for (const int idx : readUnsatAssumptions(sess)) {
            const int k = idx - first;
            if (k >= 0 && k < static_cast<int>(terms.size()) && !droppedr[k]) corer.push_back(k);
        }
    };
    // A solver need not give a minimal core, and one such as cvc5 names most of the ties
    // checked, so picking among them drops ties that fit. Once a core holds more than a few,
    // the ties left are taken in an order, the widest first and those alike at random, and
    // each conflict is the first tie that conflicts with those before it, so it is in a
    // minimal core: found by checking ever longer prefixes from the one known to fit, then
    // bisecting, and dropped unless the core of its prefix is small, to pick from as usual.
    std::vector<int> order;  // Ties in that order, once a core was large
    size_t fits = 0;  // How many of them are known to fit
    // The next conflict into corer: 1 if found, 0 if every tie left fits, -1 if cut short
    const auto nextConflict = [&](std::vector<int>& corer) VL_REQUIRES(sess.m_mutex) {
        // Only ties left; those of the prefix that fits still fit
        size_t kept = 0;
        size_t keptFits = 0;
        for (size_t i = 0; i < order.size(); ++i) {
            if (droppedr[order[i]]) continue;
            if (i < fits) ++keptFits;
            order[kept++] = order[i];
        }
        order.resize(kept);
        fits = keptFits;
        const auto check = [&](size_t n) VL_REQUIRES(sess.m_mutex) {
            --checksLeftr;
            // Marked in the solver's log as checks of a prefix
            os << "; prefix\n(check-sat-assuming (" << keep;
            for (size_t i = 0; i < n; ++i) os << " __Va" << first + order[i];
            os << "))\n";
            // Not counted as a satisfied check: a prefix fitting is no part of the result
            const VlSolverStatus status = sess.readStatus();
            if (status == VlSolverStatus::UNSAT) coreTerms(corer);
            return status;
        };
        size_t lo = fits;  // A prefix of this many fits
        size_t hi = 0;  // A prefix of this many conflicts, once known
        size_t step = 1;  // Past lo, while hi is not known
        std::vector<int> prefixCore;  // The core of the prefix hi
        while (!hi || hi - lo > 1) {
            if (checksLeftr <= 0) return -1;
            const size_t n = hi ? (lo + hi) / 2 : std::min(lo + step, order.size());
            const VlSolverStatus status = check(n);
            if (status == VlSolverStatus::UNSAT) {
                hi = n;
                prefixCore = corer;
            } else if (status != VlSolverStatus::SAT) {
                return -1;
            } else if (n == order.size()) {
                return 0;
            } else {
                lo = n;
                step *= 2;
            }
        }
        fits = lo;
        if (prefixCore.size() > static_cast<size_t>(diversityCoreFew)) {
            prefixCore.assign(1, order[lo]);
        }
        corer.swap(prefixCore);
        return 1;
    };
    while (checksLeftr > 0) {
        std::vector<int> core;
        if (order.empty()) {
            --checksLeftr;
            os << "(check-sat-assuming (" << keep;
            for (size_t k = 0; k < terms.size(); ++k) {
                if (!droppedr[k]) os << " __Va" << first + k;
            }
            os << "))\n";
            const VlSolverStatus status = sess.readStatus();
            if (status == VlSolverStatus::SAT) return true;
            // Unknown or failure: the solution already written stands
            if (status != VlSolverStatus::UNSAT) return false;
            coreTerms(core);
            if (core.size() > static_cast<size_t>(diversityCoreFew)) {
                for (size_t k = 0; k < terms.size(); ++k) {
                    if (!droppedr[k]) order.push_back(static_cast<int>(k));
                }
                for (size_t i = order.size(); i > 1; --i) {
                    std::swap(order[i - 1], order[VL_RANDOM_RNG_I(rngr) % i]);
                }
                std::stable_sort(order.begin(), order.end(),
                                 [&](int a, int b) { return terms[a].width > terms[b].width; });
            }
        }
        if (!order.empty()) {
            const int found = nextConflict(core);
            if (found == 0) return true;
            if (found < 0) return false;
        }
        // Drop the narrowest term of the core: wide data rarely causes the conflict.
        // The core only names active literals; ones before first are kept literals.
        // A core need not be minimal, so a pick among several is only a guess. Among the
        // same part of several elements of one array, the pick is random: the solver
        // lists a core in its own order, so its first would be the one to change on every
        // call.
        int pick = -1;
        int candidates = 0;
        int ties = 0;  // Candidates like the pick, which is a random one of them
        for (const int k : core) {
            ++candidates;
            if (pick < 0 || terms[k].width < terms[pick].width) {
                pick = k;
                ties = 1;
            } else if (terms[k].width == terms[pick].width && terms[k].varp == terms[pick].varp
                       && terms[k].lsb == terms[pick].lsb
                       && VL_RANDOM_RNG_I(rngr) % static_cast<IData>(++ties) == 0) {
                pick = k;
            }
        }
        if (pick < 0) return false;
        droppedr[pick] = true;
        if (guessedp && candidates > 1) (*guessedp)[pick] = true;
        // Once the same part of several elements of an array conflicts, that part of the
        // others likely does too, under one foreach: drop it for all of them, so the array
        // costs a few checks rather than one per element. The elements that conflicted are
        // kept apart, as they may be ones constrained on their own (say the first one).
        // Dropped parts are checked further in solveDiversity, but single bits are not. A
        // single bit dropped with others of its unsat cores is set by those that remain,
        // but one that conflicted alone would be left to the solver, so it is dropped for
        // all only if a few of the other elements cannot take their pin either. A whole
        // element that conflicted alone may be one of the few values a constraint rules
        // out (say d[i] != 0), so it is dropped for all only if one of a few other elements
        // cannot take its pin either: spreading a large array again part by part costs a
        // check whose work grows with the square of its size.
        if (!slotIdsp) continue;
        const PinTerm& pickTerm = terms[pick];
        const auto slotOf = [](const PinTerm& term) {
            return std::make_tuple(term.varp, term.lsb, term.width,
                                   term.width == 1 ? term.value0 : 0);
        };
        std::pair<int, bool>& conflicts = slotConflicts[slotOf(pickTerm)];
        const auto leftIt = oneByOneLeft.find(slotOf(pickTerm));
        const bool spent = leftIt != oneByOneLeft.end() && --leftIt->second < 0;
        if (!spent) {
            if (conflicts.first++ == 0) conflicts.second = true;
            conflicts.second &= candidates > 1;
            if (conflicts.first < diversitySlotConflicts) continue;
        }
        std::vector<size_t> members;
        for (size_t k = 0; k < terms.size(); ++k) {
            if (!droppedr[k] && slotOf(terms[k]) == slotOf(pickTerm)) members.push_back(k);
        }
        const bool single = pickTerm.width == 1;
        bool othersFit = false;
        if (!spent && !conflicts.second && (single || pickTerm.width == pickTerm.varp->width())) {
            othersFit = !single;  // Single bits need one sample to fit, elements all of them
            for (size_t i = 0; i < std::min<size_t>(diversitySlotSamples, members.size()); ++i) {
                if (checksLeftr-- <= 0) return false;
                os << "(check-sat-assuming (" << keep << " __Va"
                   << first + members[diversitySample(i, members.size())] << "))\n";
                const VlSolverStatus sampled = sess.readStatus();
                // Cut short or failed: the solution already written stands
                if (sampled != VlSolverStatus::SAT && sampled != VlSolverStatus::UNSAT) {
                    return false;
                }
                const bool fit = sampled == VlSolverStatus::SAT;
                if (fit && --*satisfiedLeftp <= 0) checksLeftr = 0;
                if (single == fit) {
                    othersFit = fit;
                    break;
                }
            }
        }
        if (othersFit) {
            // They go one by one, and whole elements from now on, up to a few: sampling them
            // again would spend the satisfied checks a large array needs
            conflicts.first = single ? 0 : std::numeric_limits<int>::min();
            if (!single) {
                oneByOneLeft[slotOf(pickTerm)] = std::min<int>(checksLeftr / diversitySlotShare,
                                                               members.size() / diversitySlotFew);
            }
            continue;
        }
        for (const size_t k : members) {
            droppedr[k] = true;
            (*slotIdsp)[k] = nslots;
        }
        ++nslots;
    }
    return false;
}

bool VlRandomizer::readValues(VlSolverSession& sess, const std::vector<PinTerm>& terms,
                              std::vector<std::string>& valuesr) VL_REQUIRES(sess.m_mutex) {
    std::string reply;
    if (!sess.readSExpr(reply)) return false;
    if (isSolverError(reply)) {
        sess.warnReply(reply);
        return false;
    }
    // Each value is the last term of its (term value) pair
    std::istringstream is{reply};
    char c = 0;
    is >> c;  // The '(' opening the readSExpr-balanced reply
    while (is >> c && c == '(') {
        if (valuesr.size() == terms.size()) return false;
        (void)readSMTTerm(is);
        std::string value = readSMTLastTerm(is);
        const int width = terms[valuesr.size()].width;
        smtIndexedToBinary(value, width);
        if (!validSMTNum(value) || !smtValueOfWidth(value, width)) return false;
        valuesr.push_back(value);
    }
    return c == ')' && valuesr.size() == terms.size();
}

// Re-add softs highest-priority first, dropping incompatible ones.
VlSolverStatus VlRandomizer::relaxSoftConstraints(VlSolverSession& sess)
    VL_REQUIRES(sess.m_mutex) {
    // A soft is kept when it fits the hard constraints and the higher-priority softs kept
    // so far; the last soft has the highest priority. A chunk of softs that fits together
    // is kept as a whole, as each would be on its own. A chunk that conflicts is halved
    // until the dropped soft is found alone (once its first half fits, the rest conflicts
    // without a check), and chunks grow again while they fit. So a few dropped softs among
    // n cost O(log n) checks each, rather than one check per soft; when most softs are
    // dropped, it takes up to about 1.5 checks per soft.
    std::iostream& os = sess.os();
    const size_t nsofts = m_softConstraints.size();
    size_t chunk = nsofts;  // First try all of them
    size_t conflictEnd = 0;  // End of the last conflicting chunk, whose rest still conflicts
    for (size_t done = 0; done < nsofts;) {
        chunk = std::min(chunk, nsofts - done);
        if (done + chunk != conflictEnd) {
            os << "(push 1)\n";
            for (size_t i = done; i < done + chunk; ++i) {
                os << "(assert (= #b1 " << m_softConstraints[nsofts - 1 - i] << "))\n";
            }
            os << "(check-sat)\n";
            const VlSolverStatus status = sess.readStatus();
            if (status != VlSolverStatus::SAT && status != VlSolverStatus::UNSAT) return status;
            if (status == VlSolverStatus::SAT) {
                done += chunk;
                chunk = done < conflictEnd ? conflictEnd - done : chunk * 2;
                continue;
            }
            os << "(pop 1)\n";
            conflictEnd = done + chunk;
        }
        if (chunk == 1) {
            ++done;  // Dropped
        } else {
            chunk /= 2;
        }
    }
    return VlSolverStatus::SAT;
}

// Every complete run of digits in the reply, in order
static std::vector<int> scanIntRuns(const std::string& reply) {
    std::vector<int> idxs;
    std::string num;
    for (const char c : reply) {
        // Cap the run so a garbled reply cannot overflow std::stoi
        if (std::isdigit(static_cast<unsigned char>(c)) && num.size() < 9) {
            num += c;
        } else if (!num.empty()) {
            idxs.push_back(std::stoi(num));
            num.clear();
        }
    }
    if (!num.empty()) idxs.push_back(std::stoi(num));
    return idxs;
}

std::vector<int> VlRandomizer::readUnsatAssumptions(VlSolverSession& sess)
    VL_REQUIRES(sess.m_mutex) {
    sess.os() << "(get-unsat-assumptions)\n";
    std::string reply;
    if (!sess.readSExpr(reply)) return {};
    if (isSolverError(reply)) {
        sess.warnReply(reply);
        return {};
    }
    // The response lists only "__Va<N>" literals; collect each full integer run.
    return scanIntRuns(reply);
}

// Re-solve with named asserts so an unsat core can name the failing constraints
bool VlRandomizer::exclude_sizes() {
    std::ostringstream os;
    os << "(__Vbv (not (and true";
    // In name order, so the solver is given the same text from run to run
    for (const std::string& name : std::set<std::string>{m_sizeVars.begin(), m_sizeVars.end()}) {
        const auto it = m_vars.find(name);
        if (it == m_vars.end() || it->second->width() > VL_IDATASIZE) continue;
        const IData value = *static_cast<const IData*>(it->second->datap(0));
        os << " (= " << name << " #x" << std::hex << std::setw(8) << std::setfill('0') << value
           << std::dec << ")";
    }
    os << ")))";
    m_sizeExclusions.push_back(os.str());
    return true;
}

bool VlRandomizer::report_unsat() {
    VlSolverSession& sess = s_solverSession;
    const VerilatedLockGuard lock{sess.m_mutex};
    std::vector<std::string> uniqueExprs = buildUniqueExprs();
    addAliasExprs(uniqueExprs);
    uniqueExprs.insert(uniqueExprs.end(), m_sizeExclusions.begin(), m_sizeExclusions.end());
    // Like a solve, in a transaction, so the next solve starts afresh
    VlSolverTxn txn{sess};
    if (txn.ok()) reportUnsatSetup(sess, uniqueExprs);
    return true;
}

void VlRandomizer::reportUnsatSetup(VlSolverSession& sess,
                                    const std::vector<std::string>& uniqueExprs)
    VL_REQUIRES(sess.m_mutex) {
    std::iostream& os = sess.os();
    os << "(set-option :produce-unsat-cores true)\n";
    os << "(set-logic "
       << (constraintsUseConstArray(m_constraints) || tablesNeed(TABLE_CONST_ARRAY) ? "ALL"
                                                                                    : "QF_ABV")
       << ")\n";
    emitDefines(os);
    emitDeclares(os, false);
    emitAsserts(os, uniqueExprs, true);
    os << "(check-sat)\n";
    if (sess.readStatus() == VlSolverStatus::UNSAT) reportUnsatCore(sess);
}

void VlRandomizer::reportUnsatCore(VlSolverSession& sess) VL_REQUIRES(sess.m_mutex) {
    sess.os() << "(get-unsat-core)\n";
    std::string reply;
    if (!sess.readSExpr(reply)) return;
    if (isSolverError(reply)) {
        sess.warnReply(reply);
        return;
    }
    const std::vector<int> numbers = scanIntRuns(reply);
    if (Verilated::threadContextp()->warnUnsatConstr()) {
        for (const int n : numbers) {
            if (static_cast<size_t>(n) < m_constraints_line.size()) {
                const std::string& constraint_info = m_constraints_line[n];
                // Parse "filename:linenum   source" format, parts optional
                std::string filename;
                int linenum = 0;
                std::string source = constraint_info;
                const size_t colon_pos = constraint_info.find(':');
                if (colon_pos != std::string::npos) {
                    filename = constraint_info.substr(0, colon_pos);
                    const size_t space_pos = constraint_info.find("   ", colon_pos);
                    const size_t num_end
                        = space_pos == std::string::npos ? constraint_info.size() : space_pos;
                    linenum = std::atoi(
                        constraint_info.substr(colon_pos + 1, num_end - colon_pos - 1).c_str());
                    source = space_pos == std::string::npos
                                 ? ""
                                 : constraint_info.substr(space_pos + 3);
                }
                std::string msg = "UNSATCONSTR: Unsatisfied constraint";
                const size_t start = source.find_first_not_of(" \t");
                if (start != std::string::npos) msg += ": '" + source.substr(start) + "'";
                VL_WARN_MT(filename.c_str(), linenum, "", msg.c_str());
            }
        }
    }
}

bool VlRandomizer::applyModel(VlSolverSession& sess) VL_REQUIRES(sess.m_mutex) {
    std::iostream& os = sess.os();
    // Writes the terms asking for the model's values, and returns how many variables and
    // elements they ask for. A large one-dimensional array is asked whole, into wholep if
    // given: a solver can take time linear in the array for each of its elements asked
    const auto emitTerms = [&](std::ostream& termsr, std::unordered_set<std::string>* wholep) {
        size_t requested = 0;
        for (const auto& var : m_vars) {
            // The solve of the array sizes writes only the sizes (parseModel), so asks only them
            if (m_sizeSolve && !m_sizeVars.count(var.first)) continue;
            const VlRandomVar& varr = *var.second;
            if (varr.dimension() > 0) {
                auto arrVarsp = std::make_shared<const ArrayInfoMap>(m_arr_vars);
                varr.setArrayInfo(arrVarsp);
                const int count = varr.countMatchingElements(m_arr_vars, varr.name());
                requested += count;
                const auto firstIt = m_arr_vars.find({varr.name(), 0});
                // A scalar array has no solver array; see elemTerm
                if (wholep && count > modelWholeRead && varr.isArray() && varr.dimension() == 1
                    && !varr.scalar() && firstIt != m_arr_vars.end()
                    && firstIt->second->m_idxWidths[0] <= VL_IDATASIZE) {
                    wholep->insert(varr.name());
                    termsr << ' ' << varr.name();
                    continue;
                }
            } else {
                ++requested;
            }
            varr.emitGetValue(termsr);
        }
        return requested;
    };
    // Sends a (get-value) of terms and reads its reply; false without one
    const auto ask = [&](const std::string& terms, std::string& replyr) VL_REQUIRES(sess.m_mutex) {
        os << "(get-value (" << terms << "))\n";
        return sess.readSExpr(replyr);
    };
    // Whether a reply is an error, warned of
    const auto rejected = [&](const std::string& reply) VL_REQUIRES(sess.m_mutex) {
        if (!isSolverError(reply)) return false;
        sess.warnReply(reply);
        return true;
    };
    std::unordered_set<std::string> whole;  // The arrays asked whole
    std::stringstream getValueStr;
    const size_t requested = emitTerms(getValueStr, &whole);
    if (getValueStr.str() == "") {
        // Mark as m_checkOnly to skip generation of any subsequent solver calls
        m_checkOnly = true;
        return true;
    }
    std::string reply;
    if (!ask(getValueStr.str(), reply)) return false;
    // A solver may reject asking an array whole, or answer with a value of a form not read
    bool fallback = !whole.empty() && isSolverError(reply);
    if (!fallback) {
        if (rejected(reply)) return false;
        std::istringstream is{reply};
        const bool parsed = parseModel(is, requested, &whole, &fallback);
        if (!fallback) return parsed;
    }
    // Asked by element instead, nothing being written yet
    VL_DEBUG_IF(VL_DBG_MSGF("- randomize: array model read by element\n"););
    std::stringstream elemStr;
    emitTerms(elemStr, nullptr);
    if (!ask(elemStr.str(), reply) || rejected(reply)) return false;
    std::istringstream elemIs{reply};
    return parseModel(elemIs, requested);
}

const VlRandomVar* VlRandomizer::sizeVarp(const VlRandomVar& varr) const {
    if (varr.dimension() != 1) return nullptr;
    // The name V3SolverSmt's sizeVarName() gives a random size; the two must agree, which
    // t_constraint_solve_before_array_pins checks
    const auto it = m_vars.find("__V" + varr.name() + "_size");
    return it == m_vars.end() ? nullptr : it->second.get();
}

// The element name, as ArrayInfo names it, that a select of varr with these index terms
// names, whichever literal notation the solver answered in: each index of up to 32 bits in
// decimal, a wider one in hex without leading zeros. False if they are not one index of
// each dimension's width; the element may still not be registered.
bool VlRandomizer::elementName(const VlRandomVar& varr, std::vector<std::string> indices,
                               std::string& elementr) const {
    // One index per dimension: neither a whole array nor a select of a scalar is an element
    if (indices.size() != static_cast<size_t>(varr.dimension())) return false;
    // An element is recorded with one index per dimension, but an array with no element has
    // no entry to name one, unless its size is random: then it is a queue or dynamic array,
    // indexed by 32 bits
    const auto infoIt = m_arr_vars.find(generateKey(varr.name(), 0));
    const bool sized = infoIt == m_arr_vars.end() && sizeVarp(varr);
    if (infoIt == m_arr_vars.end() && !sized) return false;
    elementr = varr.name();
    for (size_t i = 0; i < indices.size(); ++i) {
        const int width = sized ? 32 : static_cast<int>(infoIt->second->m_idxWidths[i]);
        smtIndexedToBinary(indices[i], width);
        const std::string& index = indices[i];
        // Of exactly the index's width, so no digit is dropped onto another element
        if (!validSMTNum(index) || smtNumWidth(index) != static_cast<size_t>(width)) return false;
        std::vector<EData> words(VL_WORDS_I(width), 0);
        parseSMTNum(width, WDataOutP::external(words.data()), index);
        if (width <= VL_IDATASIZE) {
            elementr += "[" + std::to_string(words[0]) + "]";
        } else {
            std::ostringstream hex;
            hex << std::hex;
            for (size_t w = words.size(); w > 0; --w) {
                hex << std::setw(8) << std::setfill('0') << words[w - 1];
            }
            std::string hexStr = hex.str();
            hexStr.erase(0, hexStr.find_first_not_of('0'));
            elementr += "[" + (hexStr.empty() ? "0" : hexStr) + "]";
        }
    }
    return true;
}

bool VlRandomizer::parseModel(std::istream& is, size_t requested,
                              const std::unordered_set<std::string>* wholep, bool* fallbackp) {
    // Quasi-parse S-expression of the form ((x #xVALUE) (y #bVALUE) (z #xVALUE))
    char c = 0;
    is >> c;  // The '(' opening the readSExpr-balanced reply
    // Stage writes; commit only after the whole reply parses so failure keeps prior values
    std::vector<std::tuple<const VlRandomVar*, std::string, std::string>> staged;
    // Every requested term must come back exactly once, whether or not it is written
    std::set<std::string> answered;
    // Array base name -> its registered elements by name, as the reply names them
    std::unordered_map<std::string, std::unordered_map<std::string, const ArrayInfo*>>
        elementsByName;
    while (true) {
        if (VL_UNCOVERABLE(!(is >> c))) return false;  // Balanced reply breaks at ')' first
        if (c == ')') break;
        if (c != '(') {
            VL_WARN_MT(__FILE__, __LINE__, "randomize",
                       "Internal: Unable to parse solver's response: invalid S-expression");
            return false;
        }
        std::string idx;
        std::vector<std::string> indices;
        const std::string term = readSMTTerm(is);
        std::string value = readSMTLastTerm(is);
        // A scalar array's element is named by its own constant
        const auto scalarIt = m_scalarElems.find(term);
        const std::string name = termVarName(term, indices);
        const auto it = m_vars.find(name);
        if (it == m_vars.end()) {
            VL_WARN_MT(__FILE__, __LINE__, "randomize",
                       "Internal: Unable to parse solver's response: unknown variable");
            return false;
        }
        const VlRandomVar& varr = *it->second;
        // Not written, though answered and checked like any other
        bool skipped = false;
        if (!varr.randModeIdxNone()) {
            // Static rand vars have their rand_mode in a class-package shared queue,
            // not the per-instance one.
            const VlQueue<CData>* const modep
                = m_staticVars.count(name) ? m_static_randmodep : m_randmodep;
            skipped = modep && !modep->at(varr.randModeIdx());
        }
        skipped
            = skipped || m_disabledVars.count(name) || (m_sizeSolve && !m_sizeVars.count(name));
        // An array asked whole (see applyModel): each element registered, from the stores
        if (wholep && wholep->count(name) && indices.empty()) {
            std::unordered_map<IData, std::string> stores;
            std::string base;
            const auto firstIt = m_arr_vars.find({name, 0});
            if (firstIt == m_arr_vars.end()
                || !smtArrayStores(value, firstIt->second->m_idxWidths[0], varr.width(), stores,
                                   base)) {
                *fallbackp = true;
                return false;
            }
            for (int k = 0;; ++k) {
                const auto elemIt = m_arr_vars.find({name, k});
                if (elemIt == m_arr_vars.end()) break;
                const ArrayInfo& info = *elemIt->second;
                if (!answered.insert(info.m_name).second) {
                    VL_WARN_MT(__FILE__, __LINE__, "randomize",
                               "Internal: Unable to parse solver's response: repeated variable");
                    return false;
                }
                if (skipped) continue;
                const auto storeIt = stores.find(info.m_indices[0]);
                std::ostringstream ss;
                ss << "#x" << std::hex << std::setw(8) << std::setfill('0') << info.m_index;
                staged.emplace_back(&varr, ss.str(),
                                    storeIt == stores.end() ? base : storeIt->second);
            }
            continue;
        }
        smtIndexedToBinary(value, varr.width());
        std::string element = varr.name();
        if (scalarIt != m_scalarElems.end()) {
            const ArrayInfo& info = *scalarIt->second.second;
            element = info.m_name;
            std::ostringstream ss;
            ss << "#x" << std::hex << std::setw(8) << std::setfill('0') << info.m_index;
            idx = ss.str();
        } else if (varr.dimension() || !indices.empty()) {
            // An index within the sort can still name no registered element
            const ArrayInfo* infop = nullptr;
            if (elementName(varr, indices, element)) {
                // The elements of the array by name, listed once for the reply
                const std::string base = generateKey(element, 0).first;
                auto& elems = elementsByName[base];
                if (elems.empty()) {
                    for (auto elemIt = m_arr_vars.lower_bound({base, 0});
                         elemIt != m_arr_vars.end() && elemIt->first.first == base; ++elemIt) {
                        elems.emplace(elemIt->second->m_name, elemIt->second.get());
                    }
                }
                const auto found = elems.find(element);
                if (found != elems.end()) infop = found->second;
            }
            if (!infop) {
                VL_WARN_MT(__FILE__, __LINE__, "randomize",
                           "Internal: Unable to parse solver's response: invalid array index");
                return false;
            }
            std::ostringstream ss;
            ss << "#x" << std::hex << std::setw(8) << std::setfill('0') << infop->m_index;
            idx = ss.str();
        }
        // By element, so the same element written in two notations is still a repeat
        if (!answered.insert(element).second) {
            VL_WARN_MT(__FILE__, __LINE__, "randomize",
                       "Internal: Unable to parse solver's response: repeated variable");
            return false;
        }
        // Reject before any commit, so a bad value later in the reply cannot leave earlier
        // ones written, and before skipping a variable not written, as a malformed reply is
        // not a model whatever is kept from it
        if (!validSMTNum(value) || !smtValueOfWidth(value, varr.width())) {
            VL_WARN_MT(__FILE__, __LINE__, "randomize",
                       "Internal: Unable to parse solver's response: invalid value");
            return false;
        }
        if (skipped) continue;
        staged.emplace_back(&varr, idx, value);
    }
    if (answered.size() != requested) {
        VL_WARN_MT(__FILE__, __LINE__, "randomize",
                   "Internal: Unable to parse solver's response: incomplete model");
        return false;
    }
    for (const auto& entry : staged) {
        keepRoundValues(*std::get<0>(entry));
        std::get<0>(entry)->set(std::get<1>(entry), std::get<2>(entry));
    }
    return true;
}

void VlRandomizer::hard(std::string constraint, std::initializer_list<const char*> varNames,
                        const char* filename, uint32_t linenum, const char* source) {
    if (VL_UNLIKELY(!m_nullReads.empty())) nullReadCheck(constraint, filename, linenum);
    m_constraints.emplace_back(std::move(constraint));
    // Stored for every constraint: a randomize() with clause registers its constraints
    // before markRandc() marks its randc variables, so whether the names are needed isn't
    // known yet here
    m_constraintVarNames.insert(m_constraintVarNames.end(), varNames.begin(), varNames.end());
    m_constraintVarEnds.push_back(m_constraintVarNames.size());
    m_constraintTablesHash.push_back(m_pendingTablesHash);
    m_pendingTablesHash = 0;
    // Format constraint location: "filename:linenum   source"
    if (filename[0] != '\0' || source[0] != '\0') {
        std::string line;
        if (filename[0] != '\0') {
            line = std::string(filename) + ":" + std::to_string(linenum);
            if (source[0] != '\0') line += "   " + std::string(source);
        } else {
            line = source;
        }
        m_constraints_line.emplace_back(std::move(line));
    }
}

void VlRandomizer::soft(std::string constraint, std::initializer_list<std::string> varNames,
                        const char* filename, uint32_t linenum, const char* /*source*/) {
    if (VL_UNLIKELY(!m_nullReads.empty())) nullReadCheck(constraint, filename, linenum);
    m_softConstraints.emplace_back(std::move(constraint));
    m_softVarNames.insert(m_softVarNames.end(), varNames.begin(), varNames.end());
    m_softVarEnds.push_back(m_softVarNames.size());
    m_pendingTablesHash = 0;
}

void VlRandomizer::disable_soft(const std::string& varName) {
    m_fastDisabled = true;  // Retain the existing conditional disable-soft protocol
    // IEEE 1800-2023 18.5.13.2: Remove the soft constraints the variable directly appears in,
    // in one pass keeping the order of the others
    size_t kept = 0;
    size_t keptNames = 0;
    size_t begin = 0;
    for (size_t i = 0; i < m_softConstraints.size(); ++i) {
        const size_t end = m_softVarEnds[i];
        const bool named
            = std::find(m_softVarNames.begin() + begin, m_softVarNames.begin() + end, varName)
              != m_softVarNames.begin() + end;
        if (!named) {
            if (kept != i) m_softConstraints[kept] = std::move(m_softConstraints[i]);
            // Names move only once an earlier constraint was removed, never onto themselves
            if (keptNames != begin) {
                std::move(m_softVarNames.begin() + begin, m_softVarNames.begin() + end,
                          m_softVarNames.begin() + keptNames);
            }
            keptNames += end - begin;
            m_softVarEnds[kept++] = keptNames;
        }
        begin = end;
    }
    m_softConstraints.resize(kept);
    m_softVarNames.resize(keptNames);
    m_softVarEnds.resize(kept);
}

void VlRandomizer::set_nested_busy(bool flag) {
    m_nestedBusy = flag;
    m_nestedNames.clear();
    if (flag) {
        for (const auto& pair : m_vars) {
            if (!pair.second->isArray()) m_nestedNames.emplace(pair.second->datap(0), pair.first);
        }
    }
}

void VlRandomizer::merge_nested(const VlRandomizer& from, const std::string& path) {
    m_fastDisabled = true;  // The merged constraints are solved, not sampled
    auto& nested = m_nested[path];
    // The constraints of 'from' are kept as they are, in an SMT let binding the names of its
    // variables to their names here: those registered here for the same storage, else the
    // names prefixed by the path. All its variables are bound, as the names each constraint
    // records (for randc) are not complete, e.g. not those formatted at runtime.
    std::string bindings;
    std::unordered_map<std::string, std::string> renames;  // Its variable names to names here
    for (const auto& pair : from.m_vars) {
        const VlRandomVar& var = *pair.second;
        const std::string name = mergeVar(from, pair.first, path, nested.first);
        if (from.isFrozenVar(pair.first, var) && m_disabledVars.insert(name).second) {
            nested.second.push_back(name);
        }
        if (from.m_randcVarNames.count(pair.first)) m_randcVarNames.insert(name);
        // The compiler keeps the arrays of a merged object whole (SolverScalarArrayVisitor)
        // LCOV_EXCL_START
        if (VL_UNCOVERABLE(var.scalar()))
            VL_FATAL_MT(__FILE__, __LINE__, "randomize", "Internal: Merged scalar array");
        // LCOV_EXCL_STOP
        bindings += " (" + pair.first + " " + name + ")";
        renames.emplace(pair.first, name);
    }
    // Its fresh constants (see fresh_const()) are constants of their own here
    for (const std::string& fresh : from.m_freshVars) {
        const std::string name = "__Vf" + std::to_string(m_freshVars.size());
        m_freshVars.push_back(name);
        bindings += " (" + fresh + " " + name + ")";
    }
    const std::string letBegin = bindings.empty() ? "" : "(let (" + bindings + ") ";
    const std::string letEnd = bindings.empty() ? "" : ")";
    // Its tables, under their names, read through the same binding
    for (size_t j = 0; j < from.m_tables.size(); ++j) {
        m_tables.push_back(letBegin + from.m_tables[j] + letEnd);
        m_tableHeads.push_back(from.m_tableHeads[j]);
        m_tableNames.push_back(from.m_tableNames[j]);
        m_tableNeeds.push_back(from.m_tableNeeds[j]);
    }
    for (size_t i = 0; i < from.m_constraints.size(); ++i) {
        m_constraints.push_back(letBegin + from.m_constraints[i] + letEnd);
        m_constraintVarEnds.push_back(m_constraintVarNames.size());
        m_constraintTablesHash.push_back(from.m_constraintTablesHash[i]);
        if (i < from.m_constraints_line.size()) {
            m_constraints_line.push_back(from.m_constraints_line[i]);
        }
    }
    size_t softBegin = 0;
    for (size_t i = 0; i < from.m_softConstraints.size(); ++i) {
        m_softConstraints.push_back(letBegin + from.m_softConstraints[i] + letEnd);
        for (size_t n = softBegin; n < from.m_softVarEnds[i]; ++n) {
            m_softVarNames.push_back(renamedVar(renames, from.m_softVarNames[n]));
        }
        m_softVarEnds.push_back(m_softVarNames.size());
        softBegin = from.m_softVarEnds[i];
    }
    for (const auto& pin : from.m_frozenPins) {
        m_frozenPins.emplace_back(renamedVar(renames, pin.first), letBegin + pin.second + letEnd);
    }
    // Arrays whose elements are to be distinct, under keys of their own here, above those the
    // holder's own constraints use
    uint32_t key = std::max(m_uniqueArrays.empty() ? 0 : m_uniqueArrays.rbegin()->first + 1,
                            uint32_t{s_mergedUniqueKey});
    for (const auto& keyNames : from.m_uniqueArrays) {
        std::unordered_set<std::string>& names = m_uniqueArrays[key++];
        for (const std::string& name : keyNames.second) names.insert(renamedVar(renames, name));
    }
    for (const auto& pair : from.m_solveBefore) {
        m_solveBefore.emplace_back(
            SolveBeforeRef{renamedVar(renames, pair.first.name), pair.first.lsb, pair.first.width},
            SolveBeforeRef{renamedVar(renames, pair.second.name), pair.second.lsb,
                           pair.second.width});
    }
}

std::string VlRandomizer::mergeVar(const VlRandomizer& from, const std::string& fromName,
                                   const std::string& path, std::vector<std::string>& addedr) {
    const VlRandomVar& var = *from.m_vars.at(fromName);
    const std::string name = path + "." + fromName;
    if (var.isArray()) {
        // Named by its elements, so registered here by name
        if (m_vars.emplace(name, var.renamed(name)).second) {
            mergeArrayElements(from, fromName, name);
            addedr.push_back(name);
        }
        return name;
    }
    // One registered here for the same storage keeps its name
    const auto pair = m_nestedNames.emplace(var.datap(0), name);
    if (pair.second) {
        m_vars[name] = var.renamed(name);
        addedr.push_back(name);
    }
    return pair.first->second;
}

void VlRandomizer::mergeArrayElements(const VlRandomizer& from, const std::string& fromName,
                                      const std::string& name) {
    for (int idx = 0;; ++idx) {
        const auto it = from.m_arr_vars.find(generateKey(fromName, idx));
        if (it == from.m_arr_vars.end()) break;
        const ArrayInfo& info = *it->second;
        // The element's name is the array's, possibly with its indices
        m_arr_vars[generateKey(name, idx)] = std::make_shared<const ArrayInfo>(
            name + info.m_name.substr(fromName.size()), info.m_datap, info.m_index, info.m_indices,
            info.m_idxWidths);
    }
}

std::string VlRandomizer::renamedVar(const std::unordered_map<std::string, std::string>& renames,
                                     const std::string& name) {
    const auto it = renames.find(name);
    return it == renames.end() ? name : it->second;
}

void VlRandomizer::clear_nested(const std::string& path) {
    const auto it = m_nested.find(path);
    if (it == m_nested.end()) return;
    for (const std::string& name : it->second.first) {
        const auto varIt = m_vars.find(name);
        if (varIt != m_vars.end() && !varIt->second->isArray()) {
            m_nestedNames.erase(varIt->second->datap(0));
        }
        clear_arr_table(name);
        m_vars.erase(name);
        m_randcVarNames.erase(name);
    }
    for (const std::string& name : it->second.second) m_disabledVars.erase(name);
    m_nested.erase(it);
    // So are the holder's own reads through the path, as its handles may hold other objects
    // now: the holder registers them again with its constraints, after the merges, whose
    // names they would otherwise give (see set_nested_busy)
    const std::string prefix = path + ".";
    auto varIt = m_vars.lower_bound(prefix);
    while (varIt != m_vars.end() && varIt->first.compare(0, prefix.size(), prefix) == 0) {
        if (!varIt->second->isArray()) m_nestedNames.erase(varIt->second->datap(0));
        clear_arr_table(varIt->first);
        varIt = m_vars.erase(varIt);
    }
}

void VlRandomizer::nullReadCheck(const std::string& constraint, const char* filename,
                                 uint32_t linenum) {
    if (failed()) return;
    for (const auto& nameRead : m_nullReads) {
        // The solver name as a whole term, not a prefix of a longer one
        for (size_t pos = constraint.find(nameRead.first); pos != std::string::npos;
             pos = constraint.find(nameRead.first, pos + 1)) {
            const size_t end = pos + nameRead.first.size();
            if (end != constraint.size() && constraint[end] != ' ' && constraint[end] != ')') {
                continue;
            }
            fail_pending("randomize() constraint reads '" + nameRead.second
                             + "', a member of a null handle, so randomize() returns 0 (IEEE "
                               "1800-2023 18.5.12); warned once",
                         filename, linenum);
            return;
        }
    }
}

std::string VlRandomizer::null_read(const std::string& name, const std::string& smtName) {
    m_nullReads.emplace_back(smtName, name);
    return smtName;
}

std::string VlRandomizer::fresh_const() {
    m_freshVars.emplace_back("__Vf" + std::to_string(m_freshVars.size()));
    return m_freshVars.back();
}

std::string VlRandomizer::termVarName(const std::string& term,
                                      std::vector<std::string>& indices) const {
    const auto it = m_scalarElems.find(term);
    return it != m_scalarElems.end() ? it->second.first->name() : parseSelect(term, indices);
}

const std::string& VlRandomizer::elemTerm(const std::string& name, IData index) {
    const auto varIt = m_vars.find(name);
    if (VL_UNCOVERABLE(varIt == m_vars.end())) {
        VL_FATAL_MT(__FILE__, __LINE__, "randomize",
                    "Internal: elemTerm of an unregistered array");
    }
    const VlRandomVar& var = *varIt->second;
    var.scalar(true);
    // A one-dimensional array's element at an index is the one of that ordinal
    if (m_arr_vars.find({name, static_cast<int>(index)}) != m_arr_vars.end()) {
        return var.elementName(index);
    }
    std::string ghost;
    VlRandomVar::elementNameOf(ghost, name, index, "__Vg");
    return m_ghostElems.emplace(ghost, GhostElem{var.width(), name, index}).first->first;
}

const std::string& VlRandomizer::elemChain(const std::string& name, const std::string& index) {
    const auto varIt = m_vars.find(name);
    if (VL_UNCOVERABLE(varIt == m_vars.end())) {
        VL_FATAL_MT(__FILE__, __LINE__, "randomize", "elemChain of an unregistered array");
    }
    varIt->second->scalar(true);
    // The same index term selects the same element
    const auto it
        = std::find_if(m_chainElems.begin(), m_chainElems.end(), [&](const ChainElem& elem) {
              return elem.m_array == name && elem.m_index == index;
          });
    if (it != m_chainElems.end()) return it->m_name;
    std::string chain;
    VlRandomVar::elementNameOf(chain, name, static_cast<IData>(m_chainElems.size()), "__Vc");
    m_chainElems.push_back(ChainElem{chain, name, index});
    return m_chainElems.back().m_name;
}

// Each chain element's constant (see elemChain): the element at its index if declared, else
// the earlier chain element of the array at the same index, else a constant of its own,
// '<name>__Vu<n>', declared but not read back. Linear in the array's declared elements.
void VlRandomizer::emitChainDefines(std::ostream& os) const {
    for (size_t i = 0; i < m_chainElems.size(); ++i) {
        const ChainElem& chain = m_chainElems[i];
        const VlRandomVar& var = *m_vars.at(chain.m_array);
        std::string own;
        VlRandomVar::elementNameOf(own, chain.m_array, static_cast<IData>(i), "__Vu");
        os << "(declare-fun " << own << " () (_ BitVec " << var.width() << "))\n";
        std::string term = own;
        const auto addCase = [&](const std::string& indexTerm, const std::string& valueTerm) {
            term = "(ite (= " + chain.m_index + " " + indexTerm + ") " + valueTerm + " " + term
                   + ")";
        };
        const auto hexIndex = [](IData index) {
            std::ostringstream ss;
            ss << "#x" << std::hex << std::setw(8) << std::setfill('0') << index;
            return ss.str();
        };
        for (size_t j = 0; j < i; ++j) {
            const ChainElem& earlier = m_chainElems[j];
            if (earlier.m_array == chain.m_array) addCase(earlier.m_index, earlier.m_name);
        }
        for (const auto& ghost : m_ghostElems) {
            if (ghost.second.m_array == chain.m_array) {
                addCase(hexIndex(ghost.second.m_index), ghost.first);
            }
        }
        for (auto it = m_arr_vars.lower_bound({chain.m_array, 0});
             it != m_arr_vars.end() && it->first.first == chain.m_array; ++it) {
            const IData index = it->second->m_indices[0];
            addCase(hexIndex(index), var.elementName(index));
        }
        os << "(define-fun " << chain.m_name << " () (_ BitVec " << var.width() << ") " << term
           << ")\n";
    }
}

void VlRandomizer::clearConstraints() {
    m_ghostElems.clear();
    m_chainElems.clear();
    m_nullReads.clear();
    m_failPending.clear();
    m_failFilename = nullptr;
    m_fastConstraints.clear();
    m_fastDisabled = false;
    m_constraints.clear();
    m_freshVars.clear();
    m_constraintVarNames.clear();
    m_constraintVarEnds.clear();
    m_constraints_line.clear();
    m_solveBefore.clear();
    m_softConstraints.clear();
    m_softVarNames.clear();
    m_softVarEnds.clear();
    // What merge_nested() added, also under the names it found for the same storage, as the
    // handles may hold other objects for the merges that follow (see clear_nested())
    while (!m_nested.empty()) clear_nested(m_nested.begin()->first);
    m_uniqueArrays.clear();  // Re-registered by constraint setup
    m_frozenPins.clear();  // Likewise re-added
    m_elemVarsCleared.clear();
    m_tables.clear();
    m_tableHeads.clear();
    m_tableNames.clear();
    m_tableNeeds.clear();
    m_tableIds.clear();
    m_tablesMerged = 0;
    m_pendingTablesHash = 0;
    m_constraintTablesHash.clear();
    // Keep m_vars for class member randomization
}

void VlRandomizer::clearAll() {
    m_fastConstraints.clear();
    m_fastDisabled = false;
    clearConstraints();
    m_vars.clear();
    m_enumDomains.clear();
    m_randcVarNames.clear();
    m_randcUsedValues.clear();
    m_randcConstraintHash = 0;
}

bool VlRandomizer::clear_elem_vars(const std::string& arrayName) {
    // Registered as "<arrayName>.<index>.<field>", and again for the objects the array holds
    // at each randomize(), so objects that were removed or replaced are not referenced. Each
    // constraint setup naming the array registers it, but only the first clears it, as a later
    // one would also unregister the members of its objects an earlier one registered.
    if (!m_elemVarsCleared.emplace(arrayName).second) return false;
    const std::string prefix = arrayName + ".";
    auto it = m_vars.lower_bound(prefix);
    while (it != m_vars.end() && it->first.compare(0, prefix.size(), prefix) == 0) {
        it = m_vars.erase(it);
    }
    // An array of those objects is unregistered with them, so registered again
    auto clearedIt = m_elemVarsCleared.lower_bound(prefix);
    while (clearedIt != m_elemVarsCleared.end()
           && clearedIt->compare(0, prefix.size(), prefix) == 0) {
        clearedIt = m_elemVarsCleared.erase(clearedIt);
    }
    return true;
}

void VlRandomizer::markRandc(const std::string& name) { m_randcVarNames.insert(name); }

void VlRandomizer::func_round_end(bool ok, const VlRandomizer& solvedr) {
    m_funcArgRounds.clear();
    m_funcRound = m_funcRoundLast = 0;
    // A failed call leaves the values (IEEE 1800-2023 18.6.3)
    if (!ok) solvedr.setValues(m_roundValues);
    m_roundValues.clear();
    m_roundKept.clear();
}

void VlRandomizer::func_round_start(int lastRound,
                                    std::initializer_list<std::pair<const char*, int>> argRounds) {
    m_funcArgRounds.clear();
    for (const auto& argRound : argRounds) {
        m_funcArgRounds.push_back({argRound.first, argRound.second, ""});
    }
    m_funcRound = 0;
    m_funcRoundLast = lastRound;
}

bool VlRandomizer::func_round_next(const VlRandomizer& solvedr) {
    // The values before the rounds, which another randomizer may have solved
    m_roundValues = solvedr.m_roundValues;
    m_roundKept = solvedr.m_roundKept;
    // Take the values now: code after the solve may randomize the variables again
    for (FuncArgRound& argRound : m_funcArgRounds) {
        if (argRound.round != m_funcRound) continue;
        // An argument of a derived class's constraint is not a variable of this object
        const auto it = solvedr.m_vars.find(argRound.name);
        if (it == solvedr.m_vars.end()) continue;
        std::ostringstream os;
        os << "(__Vbv (= " << argRound.name << ' ';
        it->second->emitConcreteValue(os, 0);
        os << "))";
        argRound.pin = os.str();
    }
    return ++m_funcRound <= m_funcRoundLast;
}

bool VlRandomizer::func_args_ready(std::initializer_list<const char*> names) const {
    for (const char* const name : names) {
        for (const FuncArgRound& argRound : m_funcArgRounds) {
            if (argRound.name == name && argRound.round >= m_funcRound) return false;
        }
    }
    return true;
}

void VlRandomizer::solveBefore(const std::string& beforeName, IData beforeLsb, IData beforeWidth,
                               const std::string& afterName, IData afterLsb, IData afterWidth) {
    m_solveBefore.emplace_back(SolveBeforeRef{beforeName, beforeLsb, beforeWidth},
                               SolveBeforeRef{afterName, afterLsb, afterWidth});
}

const VlRandomVar* VlRandomizer::solveBeforeVarp(const std::string& name) {
    const auto it = m_vars.find(name);
    if (it != m_vars.end()) return it->second.get();
    const auto elemIt = m_solveBeforeElems.find(name);
    if (elemIt != m_solveBeforeElems.end()) return elemIt->second.get();
    // An element "array.index...", with an index of 8 hex digits for each dimension, of an
    // array that the solver has as one variable
    std::vector<std::string> indices;
    std::string base = name;
    while (true) {
        const size_t dot = base.rfind('.');
        if (dot == std::string::npos) return nullptr;
        indices.insert(indices.begin(), base.substr(dot + 1));
        base.erase(dot);
        const auto arrIt = m_vars.find(base);
        if (arrIt == m_vars.end()
            || arrIt->second->dimension() != static_cast<int>(indices.size()))
            continue;
        // The compiler keeps an array solved before others whole (SolverScalarArrayVisitor)
        // LCOV_EXCL_START
        if (VL_UNCOVERABLE(arrIt->second->scalar()))
            VL_FATAL_MT(__FILE__, __LINE__, "randomize",
                        "Internal: Solve-before element of a scalar array");
        // LCOV_EXCL_STOP
        // An array without elements has no index widths, nor the element
        const auto firstIt = m_arr_vars.find(generateKey(base, 0));
        if (firstIt == m_arr_vars.end()) return nullptr;
        std::string term = base;
        for (size_t i = 0; i < indices.size(); ++i) {
            // Wider keys, as strings or 64-bit integers, are not named by 8 hex digits
            const size_t width = firstIt->second->m_idxWidths[i];
            if (width > 32) return nullptr;
            term = "(select " + term + " #x" + indices[i].substr(8 - width / 4) + ")";
        }
        m_solveBeforeArrays[name] = arrIt->second.get();
        return (m_solveBeforeElems[name]
                = std::make_shared<const VlRandomVar>(term, arrIt->second->width(), nullptr, 0,
                                                      std::numeric_limits<std::uint32_t>::max()))
            .get();
    }
}

bool VlRandomizer::buildSolveLayers(std::vector<std::vector<std::string>>& layersr) {
    // The pairs order bits of variables and array elements, which overlap when of the same
    // variable or element, or of an array and its element. The bits of each variable or
    // element are split at the bounds of its operands into segments, each ordered, solved and
    // pinned as a variable, so a variable is pinned only after the predecessors of each of
    // its parts. The graph nodes are the segments, a start node before and an end node after
    // the segments of each variable or element, which an operand of all its bits uses, and a
    // node per pair, after its first operand and before its second. So the edges are bounded
    // by the segments and the widths of the operands of parts.
    struct Root final {
        std::string name;  // Name of the variable or array element
        const VlRandomVar* arrayp = nullptr;  // Array of an array element, else nullptr
        std::vector<IData> bounds;  // Sorted bounds of its segments
        size_t firstNode = 0;  // Node of its first segment, then of its start and end
        bool whole = false;  // Operand of all its segments, so all are ordered
    };
    std::vector<std::pair<SolveBeforeBits, SolveBeforeBits>> pairs;
    std::map<const VlRandomVar*, Root> roots;
    m_solveBeforeElems.clear();
    m_solveBeforeArrays.clear();
    for (const auto& pair : m_solveBefore) {
        SolveBeforeBits bits[2];
        const SolveBeforeRef* const refps[2] = {&pair.first, &pair.second};
        bool ok = true;
        for (int i = 0; i < 2 && ok; ++i) ok = solveBeforeBits(*refps[i], bits[i]);
        // Only consider registered variables and elements of array variables, in range
        if (!ok) continue;
        for (int i = 0; i < 2; ++i) {
            Root& root = roots[bits[i].rootp];
            root.name = refps[i]->name;
            root.arrayp = bits[i].arrayp;
            root.bounds.push_back(bits[i].lo);
            root.bounds.push_back(bits[i].hi);
        }
        pairs.emplace_back(bits[0], bits[1]);
    }
    size_t nodes = 0;
    for (auto& it : roots) {
        std::vector<IData>& bounds = it.second.bounds;
        std::sort(bounds.begin(), bounds.end());
        bounds.erase(std::unique(bounds.begin(), bounds.end()), bounds.end());
        it.second.firstNode = nodes;
        nodes += bounds.size() + 1;
    }
    const size_t pairNode0 = nodes;
    nodes += pairs.size();
    // Edges, with the number of layers the node after is at least after the node before
    std::vector<std::vector<std::pair<size_t, size_t>>> succs(nodes);
    std::vector<size_t> inDegree(nodes, 0);
    std::vector<bool> ordered(nodes, false);  // Segment of a part operand, not of a gap
    const auto addEdge = [&](size_t from, size_t to, size_t layers) {
        succs[from].emplace_back(to, layers);
        ++inDegree[to];
    };
    for (const auto& it : roots) {
        const Root& root = it.second;
        const size_t start = root.firstNode + root.bounds.size() - 1;
        for (size_t node = root.firstNode; node < start; ++node) {
            addEdge(start, node, 0);
            addEdge(node, start + 1, 0);
        }
        // An element is part of its array, which is pinned only after it
        if (!root.arrayp) continue;
        const auto arrayIt = roots.find(root.arrayp);
        if (arrayIt == roots.end()) continue;
        const Root& array = arrayIt->second;
        const size_t arrayStart = array.firstNode + array.bounds.size() - 1;
        addEdge(arrayStart, start, 0);
        addEdge(start + 1, arrayStart + 1, 0);
        for (size_t node = array.firstNode; node < arrayStart; ++node) addEdge(start + 1, node, 0);
    }
    for (size_t i = 0; i < pairs.size(); ++i) {
        for (int side = 0; side < 2; ++side) {
            const SolveBeforeBits& bits = side ? pairs[i].second : pairs[i].first;
            Root& root = roots[bits.rootp];
            const auto loIt = std::lower_bound(root.bounds.begin(), root.bounds.end(), bits.lo);
            const auto hiIt = std::lower_bound(loIt, root.bounds.end(), bits.hi);
            const size_t loNode = root.firstNode + (loIt - root.bounds.begin());
            const size_t hiNode = root.firstNode + (hiIt - root.bounds.begin());
            const size_t start = root.firstNode + root.bounds.size() - 1;
            if (loNode == root.firstNode && hiNode == start) {
                root.whole = true;
                if (side) addEdge(pairNode0 + i, start, 1);
                if (!side) addEdge(start + 1, pairNode0 + i, 0);
                continue;
            }
            for (size_t node = loNode; node < hiNode; ++node) {
                ordered[node] = true;
                if (side) addEdge(pairNode0 + i, node, 1);
                if (!side) addEdge(node, pairNode0 + i, 0);
            }
        }
    }
    // Topological order, with the layer of each node
    std::vector<size_t> layer(nodes, 0);
    std::vector<size_t> ready;
    for (size_t node = 0; node < nodes; ++node) {
        if (!inDegree[node]) ready.push_back(node);
    }
    size_t done = 0;
    while (!ready.empty()) {
        const size_t node = ready.back();
        ready.pop_back();
        ++done;
        for (const auto& edge : succs[node]) {
            layer[edge.first] = std::max(layer[edge.first], layer[node] + edge.second);
            if (!--inDegree[edge.first]) ready.push_back(edge.first);
        }
    }
    if (done < nodes) {
        VL_WARN_MT("", 0, "randomize", "Circular dependency in solve-before constraints");
        return false;
    }
    for (const auto& it : roots) {
        const Root& root = it.second;
        for (size_t i = 0; i + 1 < root.bounds.size(); ++i) {
            const size_t node = root.firstNode + i;
            if (!root.whole && !ordered[node]) continue;
            const IData lo = root.bounds[i];
            const IData hi = root.bounds[i + 1];
            std::string name = root.name;
            if (lo || hi != static_cast<IData>(it.first->width())) {
                name = "((_ extract " + std::to_string(hi - 1) + " " + std::to_string(lo) + ") "
                       + it.first->name() + ")";
                m_solveBeforeElems[name] = std::make_shared<const VlRandomVar>(
                    name, static_cast<int>(hi - lo), nullptr, 0,
                    std::numeric_limits<std::uint32_t>::max());
            }
            if (layersr.size() <= layer[node]) layersr.resize(layer[node] + 1);
            layersr[layer[node]].push_back(name);
        }
    }
    for (auto& names : layersr) std::sort(names.begin(), names.end());
    return true;
}

bool VlRandomizer::solveBeforeBits(const SolveBeforeRef& ref, SolveBeforeBits& bitsr) {
    bitsr.rootp = solveBeforeVarp(ref.name);
    if (!bitsr.rootp) return false;
    const auto arrayIt = m_solveBeforeArrays.find(ref.name);
    bitsr.arrayp = arrayIt == m_solveBeforeArrays.end() ? nullptr : arrayIt->second;
    const IData varWidth = bitsr.rootp->width();
    if (!ref.width) {
        bitsr.lo = 0;
        bitsr.hi = varWidth;
        return true;
    }
    // A select by a variable index can be out of range
    if (ref.lsb >= varWidth || ref.width > varWidth - ref.lsb) return false;
    bitsr.lo = ref.lsb;
    bitsr.hi = ref.lsb + ref.width;
    return true;
}

// Whether a term multiplies, divides or takes the remainder of two operands neither of
// which is a literal. Either logic is sound, so a term this misreads only costs speed.
static bool smtHasNonlinear(const std::string& term) {
    for (const char* const opp :
         {"(bvmul ", "(bvudiv ", "(bvurem ", "(bvsdiv ", "(bvsrem ", "(bvsmod "}) {
        const std::string op{opp};
        for (size_t pos = term.find(op); pos != std::string::npos; pos = term.find(op, pos + 1)) {
            size_t i = pos + op.size();
            if (term[i] == '#') continue;
            // Past the first operand, an atom or a parenthesized term, to the second
            for (int depth = 0; i < term.size() && (depth || term[i] != ' '); ++i) {
                if (term[i] == '(') ++depth;
                if (term[i] == ')') --depth;
            }
            if (i + 1 < term.size() && term[i + 1] != '#') return true;
        }
    }
    return false;
}

bool VlRandomizer::tablesNeed(uint8_t needs) const {
    for (const uint8_t tableNeeds : m_tableNeeds) {
        if (tableNeeds & needs) return true;
    }
    return false;
}

const char* VlRandomizer::solverLogic() const {
    if (constraintsUseConstArray(m_constraints) || constraintsUseConstArray(m_softConstraints)
        || tablesNeed(TABLE_CONST_ARRAY)) {
        return "ALL";
    }
    // Without arrays, QF_BV lets z3 answer the incremental checks of the sampling with
    // its bit-blasting SAT solver, which is several times faster than the SMT core it
    // uses for QF_ABV, but many times slower once a product or quotient of variables has
    // to be inverted. Phased solves keep phasedLogic(): their XOR rounds solve slower
    // with QF_BV.
    for (const auto& var : m_vars) {
        if (var.second->dimension() > 0 && !var.second->scalar()) return "QF_ABV";
    }
    // A constraint may hold an array term of its own, such as an array literal, also in a
    // table it calls
    if (tablesNeed(TABLE_ARRAY_TERMS)) return "QF_ABV";
    for (const auto* const constraintsp : {&m_constraints, &m_softConstraints}) {
        for (const std::string& constraint : *constraintsp) {
            if (constraint.find("(Array ") != std::string::npos) return "QF_ABV";
            if (smtHasNonlinear(constraint)) return "QF_ABV";
        }
    }
    return "QF_BV";
}

const char* VlRandomizer::phasedLogic() const {
    if (constraintsUseConstArray(m_constraints) || constraintsUseConstArray(m_softConstraints)
        || tablesNeed(TABLE_CONST_ARRAY)) {
        return "ALL";
    }
    for (const auto& var : m_vars) {
        if (var.second->dimension() == 0) continue;
        if (!var.second->hasMatchingElements(m_arr_vars, var.second->name())) return "ALL";
    }
    return "QF_ABV";
}

bool VlRandomizer::nextPhased(VlRNG& rngr, VlSolverSession& sess,
                              const std::vector<std::string>& uniqueExprs)
    VL_REQUIRES(sess.m_mutex) {
    // Solve layer by layer with ALL constraints, pinning earlier layers
    std::vector<std::vector<std::string>> layers;
    if (!buildSolveLayers(layers)) return false;

    // No layers means no solve_before pair survived
    if (layers.empty()) return nextFlat(rngr, sess, uniqueExprs);

    VlSolverTxn txn{sess};
    if (!txn.ok()) return false;
    // Retry once with the randc cycle cleared, as nextFlat does
    bool exhausted = false;
    if (solvePhases(rngr, sess, layers, uniqueExprs, exhausted)) return true;
    if (!exhausted) return false;
    m_randcUsedValues.clear();
    sess.os() << "(reset)\n";
    return solvePhases(rngr, sess, layers, uniqueExprs, exhausted);
}

bool VlRandomizer::solvePhases(VlRNG& rngr, VlSolverSession& sess,
                               const std::vector<std::vector<std::string>>& layers,
                               const std::vector<std::string>& uniqueExprs, bool& exhaustedr)
    VL_REQUIRES(sess.m_mutex) {
    std::iostream& os = sess.os();
    std::map<std::string, std::string> solvedValues;  // varName -> SMT value literal
    const char* const logicp = phasedLogic();
    // The final phase also solves the variables outside every solve...before pair
    std::vector<std::string> finalVars = layers.back();
    if (!solverSamples()) {
        std::unordered_set<std::string> layered;
        for (const std::vector<std::string>& layer : layers)
            layered.insert(layer.begin(), layer.end());
        for (const auto& var : m_vars) {
            if (!layered.count(var.first)) finalVars.push_back(var.first);
        }
    }
    // A phase whose variables are all scalars is sampled from a base kept from the previous
    // phase (see sampleLayer). A phase with an array, a phase sampling took nothing for, and
    // the phase after a phase that kept no base build a fresh base as before.
    bool keepBase = false;
    bool rebuild = false;  // Sampling took no assignment, so solve this phase afresh

    size_t phase = 0;
    while (true) {
        const bool isFinalPhase = (phase == layers.size() - 1);
        const std::vector<std::string>& phaseVars = isFinalPhase ? finalVars : layers[phase];
        // The solver sampler seeds each phase, so it always rebuilds
        const bool sampled = !solverSamples() && !rebuild && !layerHasArray(phaseVars)
                             && sampleWorthwhile(phaseVars);
        if (keepBase && !sampled) {
            os << "(reset)\n";
            keepBase = false;
        }
        // A kept base with the previous layer's sampled pins has a model by construction
        const bool reused = keepBase;

        if (!keepBase) {
            os << "(set-option :produce-models true)\n";
            if (solverSamples()) {
                emitSolverSeed(os, rngr);
            } else {
                // Every phase's variables are spread (solvePhaseValues, solveDiversity)
                os << "(set-option :produce-unsat-assumptions true)\n";
            }
            os << "(set-logic " << logicp << ")\n";
            emitDefines(os);
            emitDeclares(os, false);

            for (const auto& entry : solvedValues) {
                os << "(assert (= " << entry.first << " " << entry.second << "))\n";
            }
            emitAsserts(os, uniqueExprs, false);

            // Randc: exclude previously used values
            emitRandcExclusions(os);

            // Soft constraints participate in every phase, priority-ordered. A relaxation
            // that succeeded settled every check, so the kept selection stays maximal under
            // this phase's pins.
            if (relaxSoftConstraints(sess) != VlSolverStatus::SAT) return false;
            keepBase = sampled;
        }

        // Initial check-sat WITHOUT diversity (guaranteed sat if constraints are consistent)
        if (!reused) {
            os << "(check-sat)\n";
            const VlSolverStatus status = sess.readStatus();
            if (status != VlSolverStatus::SAT) {
                // Only exhausted randc values are worth a retry; a lost solver is not
                if (status == VlSolverStatus::UNSAT) exhaustedr = !m_randcUsedValues.empty();
                return false;
            }
        }

        std::map<std::string, std::string> layerValues;
        if (keepBase) {
            const VlSolverStatus status
                = sampleLayer(sess, rngr, phaseVars, isFinalPhase ? nullptr : &layerValues);
            rebuild = status == VlSolverStatus::UNSAT || status == VlSolverStatus::UNKNOWN;
            if (rebuild) continue;
            if (status != VlSolverStatus::SAT) return false;
        } else if (isFinalPhase) {
            if (!applyModel(sess)) return false;
            if (!solverSamples()) {
                std::set<std::string> fixed;  // Variables of the earlier layers
                for (size_t i = 0; i < phase; ++i)
                    fixed.insert(layers[i].begin(), layers[i].end());
                sess.holdReplies(true);
                solveDiversity(rngr, sess, &fixed);
                sess.holdReplies(false);
                m_spreadFailed |= sess.failed();
            }
        } else if (!solvePhaseValues(sess, rngr, layers[phase], layerValues)) {
            return false;
        }
        rebuild = false;
        if (isFinalPhase) break;

        for (const auto& entry : layerValues) {
            if (keepBase) os << "(assert (= " << entry.first << " " << entry.second << "))\n";
            solvedValues.emplace(entry);
        }
        if (!keepBase) os << "(reset)\n";
        ++phase;
    }

    // Record solved randc values for future exclusion
    recordRandcValues();
    return true;
}

bool VlRandomizer::layerHasArray(const std::vector<std::string>& layerVars) {
    for (const std::string& name : layerVars) {
        if (solveBeforeVarp(name)->dimension() > 0) return true;
    }
    return false;
}

// Sampling a phase pays up to phaseSampleTries solver checks before a rebuild, so once a
// phase has had that many trials, it is rebuilt directly while they were satisfiable less
// than once per phaseSampleTries. As the constraints can change between calls, such a phase
// is sampled again after phaseSampleRetry calls without trials, and the counts are halved
// whenever they reach phaseSampleWindow trials, so that recent trials weigh the most. The counts
// restart with a reseed, so a result still depends only on the object's random state.
bool VlRandomizer::sampleWorthwhile(const std::vector<std::string>& phaseVars) {
    PhaseSampleStats& stats = m_phaseSampleStats[phaseVars.front()];
    if (stats.tries < phaseSampleTries || stats.accepts * phaseSampleTries >= stats.tries) {
        return true;
    }
    if (++stats.skips <= phaseSampleRetry) return false;
    stats = PhaseSampleStats{};
    return true;
}

// Sample a phase's scalars from the kept base, in scopes that leave the base unchanged.
// A solver started fresh for each phase varies its model with the pins, but a kept solver
// returns models near its last one, so the variation must come from the constraints sent.
// Up to phaseSampleTries uniformly random assignments of the variables are tried; given
// that one is satisfiable, the first such is uniform over the feasible assignments
// (rejection sampling). An intermediate phase takes the assignment into valuesp; the final
// phase writes the model to the variables. Returns SAT when an assignment was taken, UNSAT
// or UNKNOWN when none was, and FAIL when a reply was unusable.
VlSolverStatus VlRandomizer::sampleLayer(VlSolverSession& sess, VlRNG& rngr,
                                         const std::vector<std::string>& phaseVars,
                                         std::map<std::string, std::string>* const valuesp)
    VL_REQUIRES(sess.m_mutex) {
    std::iostream& os = sess.os();
    PhaseSampleStats& stats = m_phaseSampleStats[phaseVars.front()];
    std::vector<std::string> trial(phaseVars.size());
    std::vector<IData> words;
    for (int i = 0; i < phaseSampleTries; ++i) {
        os << "(push 1)\n";
        for (size_t v = 0; v < phaseVars.size(); ++v) {
            // A variable, a segment of one, or an array element
            const VlRandomVar* const varp = solveBeforeVarp(phaseVars[v]);
            const int width = varp->width();
            words.resize(VL_WORDS_I(width));
            for (IData& word : words) word = VL_RANDOM_RNG_I(rngr);
            std::string& literal = trial[v];
            literal.reserve(width + 2);
            literal = "#b";
            for (int b = width - 1; b >= 0; --b) {
                literal += VL_BITISSET_I(words[VL_BITWORD_I(b)], b) ? '1' : '0';
            }
            os << "(assert (= " << varp->name() << ' ' << literal << "))\n";
        }
        os << "(check-sat)\n";
        VlSolverStatus status = sess.readStatus();
        if (++stats.tries == phaseSampleWindow) {
            stats.tries /= 2;
            stats.accepts /= 2;
        }
        if (status == VlSolverStatus::SAT) {
            ++stats.accepts;
            if (!valuesp && !applyModel(sess)) status = VlSolverStatus::FAIL;
        }
        os << "(pop 1)\n";
        if (status != VlSolverStatus::UNSAT) {
            if (status == VlSolverStatus::SAT && valuesp) {
                for (size_t v = 0; v < phaseVars.size(); ++v) {
                    (*valuesp)[solveBeforeVarp(phaseVars[v])->name()] = trial[v];
                }
            }
            return status;
        }
    }
    return VlSolverStatus::UNSAT;
}

// Intermediate phase: extract this layer's values, then optionally try one diversity round
bool VlRandomizer::solvePhaseValues(VlSolverSession& sess, VlRNG& rngr,
                                    const std::vector<std::string>& layerVars,
                                    std::map<std::string, std::string>& solvedValuesr)
    VL_REQUIRES(sess.m_mutex) {
    std::iostream& os = sess.os();
    std::ostringstream terms;  // The terms each (get-value) asks for
    // A phase can hold an array, whose elements are all asked, and some of its elements by
    // name; each term is asked once, as first written, since a reply answers each term once
    std::unordered_set<std::string> asked;  // Keys of the terms asked
    const auto ask = [&](const std::string& text, const char* separator) {
        std::istringstream tis{text};
        for (std::string term; !(term = readSMTTerm(tis)).empty();) {
            std::string key;
            (void)phaseTermKey(term, key);  // Built from the registered variables, so found
            if (asked.emplace(key).second) terms << term << separator;
        }
    };
    std::vector<const VlRandomVar*> sized;  // Arrays pinned by element up to their size
    for (const auto& varName : layerVars) {
        const VlRandomVar* const varp = solveBeforeVarp(varName);
        if (varp->dimension() > 0) {
            auto arrVarsp = std::make_shared<const ArrayInfoMap>(m_arr_vars);
            varp->setArrayInfo(arrVarsp);
            // Enumerable arrays: query each element for a QF_ABV-safe pin.
            if (varp->hasMatchingElements(m_arr_vars, varp->name())) {
                std::ostringstream elems;
                varp->emitGetValue(elems);
                ask(elems.str(), "");
                continue;
            }
            // A solver need not take back its own model of a whole array (cvc5 rejects the
            // constant array in it), so one of a solved size is pinned by element instead,
            // in time linear in the size, which its resize allocates anyway
            if (sizeVarp(*varp)) {
                sized.push_back(varp);
                continue;
            }
        }
        ask(varp->name(), " ");
    }
    const std::string fixedTerms = terms.str();  // All but the elements of sized arrays
    // The sizes of the sized arrays in the current model, and their elements up to them, in
    // valuesr; false if a reply is unusable. Both are pinned, so that a later phase can
    // neither pick another size nor leave elements free.
    const auto readSized = [&](std::map<std::string, std::string>& valuesr) VL_REQUIRES(
                               sess.m_mutex) {
        if (sized.empty()) return true;
        std::ostringstream sizeTerms;
        for (const VlRandomVar* const varp : sized) {
            sizeTerms << sizeVarp(*varp)->name() << ' ';
        }
        os << "(get-value (" << sizeTerms.str() << "))\n";
        if (!readPhaseValues(sess, sizeTerms.str(), valuesr)) return false;
        std::ostringstream elems;
        elems << std::hex << std::setfill('0');
        for (const VlRandomVar* const varp : sized) {
            const VlRandomVar* const sizep = sizeVarp(*varp);
            std::vector<EData> words(VL_WORDS_I(sizep->width()), 0);
            parseSMTNum(sizep->width(), WDataOutP::external(words.data()), valuesr[sizep->name()]);
            for (EData j = 0; j < words[0]; ++j) {
                elems << "(select " << varp->name() << " #x" << std::setw(8) << j << ")";
            }
        }
        // Arrays of size 0 leave no element to ask for
        if (elems.str().empty()) return true;
        os << "(get-value (" << elems.str() << "))\n";
        return readPhaseValues(sess, elems.str(), valuesr);
    };
    // Get baseline values (deterministic, always valid)
    std::map<std::string, std::string> values;
    if (!fixedTerms.empty()) {
        os << "(get-value (" << fixedTerms << "))\n";
        if (!readPhaseValues(sess, fixedTerms, values)) return false;
    }
    if (!readSized(values)) return false;

    // Spread a layer of few terms, its own variables and the sizes of its sized arrays, as the
    // final phase spreads its variables, rather than leave its values to the solver. A tie
    // that conflicts is split down to bits, so a range that is not a power of two still leans
    // to the solver's choice (a residual), unless the variable's range constraints give its
    // first tie (fastTargets). A larger layer keeps one random parity over its bits:
    // spreading it would cost a check or more per term, many times the solve itself on a slow
    // solver, and the solver's choice within the parity remains (a residual too). The values
    // are then read again, with the elements up to the sizes.
    if (!solverSamples()) {
        sess.holdReplies(true);
        std::vector<PinTerm> spread;
        // A layer can hold an array and some of its elements by name: each element is spread
        // once, as first written
        std::unordered_set<std::string> spreadTexts;
        const auto add = [&](const VlRandomVar* varp) {
            // Nor one with rand_mode off, which keeps its value (IEEE 1800-2023 18.8)
            if (isFrozenVar(varp->name(), *varp)) return;
            const int width = varp->width();
            for (int j = 0; j < varp->totalWidth() / width; ++j) {
                std::ostringstream text;
                varp->emitElement(text, j);
                if (!spreadTexts.insert(text.str()).second) continue;
                spread.push_back({varp, j, 0, width, static_cast<int>(spread.size())});
            }
        };
        for (const auto& varName : layerVars) {
            const VlRandomVar* const varp = solveBeforeVarp(varName);
            if (std::find(sized.begin(), sized.end(), varp) == sized.end()) add(varp);
        }
        for (const VlRandomVar* const varp : sized) add(sizeVarp(*varp));
        bool diverse = false;  // Whether the model is to be read again
        bool unanswered = false;  // Whether a command may be unanswered
        if (spread.size() <= static_cast<size_t>(diversityLayerTerms)) {
            diverse = spreadTerms(rngr, sess, std::move(spread), nullptr);
            unanswered = !diverse;
        } else {
            // Scoped to this layer's own vars -- see randomConstraint's comment -- and the
            // sizes of its sized arrays
            std::vector<std::string> hashVars = layerVars;
            for (const VlRandomVar* const varp : sized) {
                hashVars.push_back(sizeVarp(*varp)->name());
            }
            os << "(assert ";
            randomConstraint(os, rngr, _VL_SOLVER_HASH_LEN, &hashVars);
            os << ")\n";
            os << "(check-sat)\n";
            const VlSolverStatus status = sess.readStatus();
            diverse = status == VlSolverStatus::SAT;
            unanswered = status == VlSolverStatus::FAIL;
        }
        if (diverse) {
            // An unusable reply leaves the baseline values
            std::map<std::string, std::string> rechecked;
            bool read = false;
            if (fixedTerms.empty()) {
                read = readSized(rechecked);
            } else {
                os << "(get-value (" << fixedTerms << "))\n";
                read = readPhaseValues(sess, fixedTerms, rechecked) && readSized(rechecked);
            }
            if (read) {
                values.swap(rechecked);
            } else {
                m_spreadFailed = true;
            }
        } else if (unanswered) {
            // Only the diversity commands can be unanswered, and the next phase starts with a
            // (reset), so get back in step here and keep the baseline values
            m_spreadFailed |= sess.failed();
            sess.resync();
        }
        sess.holdReplies(false);
    }
    for (const auto& entry : values) solvedValuesr[entry.first] = entry.second;
    return true;
}

bool VlRandomizer::readPhaseValues(VlSolverSession& sess, const std::string& terms,
                                   std::map<std::string, std::string>& solvedValuesr)
    VL_REQUIRES(sess.m_mutex) {
    std::string reply;
    if (!sess.readSExpr(reply)) return false;
    if (isSolverError(reply)) {
        sess.warnReply(reply);
        return false;
    }
    std::istringstream is{reply};
    return parsePhaseValues(is, terms, solvedValuesr);
}

// The key of a part of a variable or element, ((_ extract H L) <term>), parsed whatever the
// whitespace between its tokens: as buildSolveLayers names it, single-spaced, with each index
// in hex of its width, the notation solveBeforeVarp names an element by. Empty for any other
// term; an index of another width or form stays as answered, for the match to reject.
std::string VlRandomizer::partTermKey(const std::string& term) const {
    // Only a term opening with two '(' can be one: names and selects skip the parse
    const size_t open = term.find_first_not_of(" \t\r\n");
    const size_t inner
        = open == std::string::npos ? open : term.find_first_not_of(" \t\r\n", open + 1);
    if (inner == std::string::npos || term[open] != '(' || term[inner] != '(') return "";
    std::istringstream is{term};
    is.ignore(static_cast<std::streamsize>(open + 1));
    const std::string indexed = readSMTTerm(is);
    const std::string operand = readSMTTerm(is);
    std::string close;
    std::getline(is >> std::ws, close);
    if (close != ")" || indexed.size() < 2) return "";
    std::istringstream its{indexed.substr(1, indexed.size() - 2)};
    std::string under, op, hi, lo, extra;
    its >> under >> op >> hi >> lo;
    if (under != "_" || op != "extract" || lo.empty() || its >> extra) return "";
    std::vector<std::string> indices;
    const std::string base = parseSelect(operand, indices);
    const auto firstIt = m_arr_vars.find(generateKey(base, 0));
    std::string select = base;
    for (size_t i = 0; i < indices.size(); ++i) {
        const size_t width = firstIt != m_arr_vars.end() && i < firstIt->second->m_idxWidths.size()
                                 ? firstIt->second->m_idxWidths[i]
                                 : 0;
        std::string index = indices[i];
        smtIndexedToBinary(index, static_cast<int>(width));
        if (width && width <= 32 && !(width % 4) && validSMTNum(index)
            && smtNumWidth(index) == width) {
            IData value = 0;
            parseSMTNum(static_cast<int>(width), WDataOutP::external(&value), index);
            std::ostringstream hex;
            hex << "#x" << std::hex << std::setfill('0') << std::setw(width / 4) << value;
            index = hex.str();
        }
        select = "(select " + select + " " + index + ")";
    }
    return "((_ extract " + hi + " " + lo + ") " + select + ")";
}

// The variable or element a phase term names, by its key; the key is what parseModel names
// it, so a term the solver writes in another notation still matches
const VlRandomVar* VlRandomizer::phaseTermKey(const std::string& term, std::string& keyr) const {
    // A part of a variable solved before another is named by its own term, as asked
    const std::string partKey = partTermKey(term);
    if (!partKey.empty()) {
        keyr = partKey;
        const auto it = m_solveBeforeElems.find(keyr);
        return it == m_solveBeforeElems.end() ? nullptr : it->second.get();
    }
    // Not of a scalar array's element: the elements solved in an earlier phase are of
    // arrays named in solve-before, which the compiler keeps whole
    std::vector<std::string> indices;
    const std::string name = parseSelect(term, indices);
    const auto it = m_vars.find(name);
    if (it == m_vars.end()) return nullptr;
    std::string key = name;  // A scalar, or an array pinned whole
    // Pins go back to the solver, so their indices are portable literals too
    for (const std::string& index : indices) {
        if (index.compare(0, 2, "#h") == 0 || index.compare(0, 2, "#o") == 0) return nullptr;
    }
    if (!indices.empty() && !elementName(*it->second, indices, key)) return nullptr;
    keyr = key;
    return it->second.get();
}

// Reads ((term value) ...) answering the (get-value) of terms into solvedValuesr, the
// value of each term to pin in the later phases. The values go back to the solver, so the
// reply is applied only if it answers each term once with a value of the term's sort.
bool VlRandomizer::parsePhaseValues(std::istream& is, const std::string& terms,
                                    std::map<std::string, std::string>& solvedValuesr) {
    const auto fail = [](const char* why) {
        const std::string msg = std::string{"Internal: Unable to parse solver's response: "} + why;
        VL_WARN_MT(__FILE__, __LINE__, "randomize", msg.c_str());
        return false;
    };
    std::map<std::string, std::string> requested;  // Key -> term as asked
    std::istringstream tis{terms};
    for (std::string term; !(term = readSMTTerm(tis)).empty();) {
        std::string key;
        (void)phaseTermKey(term, key);  // Built from the registered variables, so always found
        requested.emplace(key, term);
    }
    std::map<std::string, std::string> staged;  // Term as asked -> value
    char c = 0;
    is >> c;  // The '(' opening the readSExpr-balanced reply
    while (true) {
        // The balanced reply breaks at its ')' first
        if (VL_UNCOVERABLE(!(is >> c))) return fail("invalid S-expression");
        if (c == ')') break;
        if (c != '(') return fail("invalid S-expression");
        std::string key;
        const VlRandomVar* const varp = phaseTermKey(readSMTTerm(is), key);
        const auto reqIt = requested.find(key);
        if (reqIt == requested.end()) return fail("unknown variable");  // So varp is set
        std::string value = readSMTLastTerm(is);
        // A scalar or element is a bit-vector; an array pinned whole is of its declared sort
        const bool wholeArray = key == varp->name() && varp->dimension();
        std::ostringstream sort;
        if (wholeArray) varp->emitType(sort);
        if (wholeArray ? !smtArrayOfSort(value, sort.str())
                       : !smtLiteralOfWidth(value, varp->width())) {
            return fail("invalid value");
        }
        if (!staged.emplace(reqIt->second, value).second) return fail("repeated variable");
    }
    if (staged.size() != requested.size()) return fail("incomplete model");
    for (const auto& entry : staged) solvedValuesr[entry.first] = entry.second;
    return true;
}

#ifdef VL_DEBUG
void VlRandomizer::dump() const {
    for (const auto& var : m_vars) {
        VL_PRINTF("Variable (%d): %s\n", var.second->width(), var.second->name().c_str());
    }
    for (const std::string& c : m_constraints) VL_PRINTF("Constraint: %s\n", c.c_str());
}
#endif
