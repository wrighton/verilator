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
static constexpr int diversityWideBits = 64;  // Parts wider than this may stay unsplit
static constexpr int diversitySlotConflicts = 4;  // Elements conflicting to drop a part of all
static constexpr int diversitySlotSamples = 4;  // Elements checked for a part dropped for all

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
    std::string m_logLinePrefix;  // Prefix of the last log line, unfinished if m_logLineOpen
    bool m_logLineOpen = false;  // Last logged text did not end its line

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
            const ssize_t n = ::write(m_writeFd, pbase() + done, size - done);
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
#ifdef _VL_SOLVER_PIPE_UNIX
        if (!m_pidExited) {
            ::kill(m_pid, SIGKILL);
            waitpid(m_pid, &m_pidStatus, 0);
        }
#elif defined(_VL_SOLVER_PIPE_WIN)
        if (!m_pidExited && m_pid) {
            TerminateProcess(m_pid, EXIT_FAILURE);
            WaitForSingleObject(m_pid, INFINITE);
            CloseHandle(m_pid);
        }
#endif
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
#ifdef _VL_SOLVER_PIPE_UNIX
        int fd_stdin[2];  // Can't use std::array
        int fd_stdout[2];  // Can't use std::array
        constexpr int P_RD = 0;
        constexpr int P_WR = 1;

        if (VL_UNLIKELY(pipe(fd_stdin) != 0)) {
            perror("VlRProcess::open: pipe");
            return false;
        }
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

        log("", "# Open: "s + cmd[0] + "\n");
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
        log("", "# Open: "s + cmd[0] + "\n");
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
    void log(const std::string& prefix, const std::string& text) {
        if (VL_LIKELY(!m_logfp.get()) || text.empty()) return;
        // Pipe buffers end anywhere, so continue an unfinished line of the same direction
        // rather than breaking it (inside a token, unreadable by a solver)
        if (m_logLineOpen && prefix != m_logLinePrefix) {
            *m_logfp << '\n';
            m_logLineOpen = false;
        }
        if (!m_logLineOpen && m_logLastTime != Verilated::threadContextp()->time()) {
            m_logLastTime = Verilated::threadContextp()->time();
            *m_logfp << "# [" << Verilated::threadContextp()->timeWithUnitString() << "]\n";
        }
        m_logLinePrefix = prefix;
        std::size_t startPos = 0;
        while (startPos < text.length()) {
            if (!m_logLineOpen) *m_logfp << prefix;
            const std::size_t endPos = text.find('\n', startPos);
            m_logLineOpen = endPos == std::string::npos;
            const std::size_t lineEnd = m_logLineOpen ? text.length() : endPos + 1;
            *m_logfp << text.substr(startPos, lineEnd - startPos);
            startPos = lineEnd;
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

static void warnSolverReply(const std::string& reply) {
    static bool s_warned = false;
    if (s_warned) return;
    s_warned = true;
    const std::string msg
        = "Solver did not answer with a status, so randomize() returns 0; warned once: " + reply;
    VL_WARN_MT(__FILE__, __LINE__, "randomize", msg.c_str());
}

// Read one solver status; only a print-success echo may precede it
static VlSolverStatus readStatus(std::istream& is) {
    std::string line;
    while (readLine(is, line)) {
        if (line == "success") continue;
        if (line == "sat") return VlSolverStatus::SAT;
        if (line == "unsat") return VlSolverStatus::UNSAT;
        if (line == "unknown") {
            static bool s_warnedUnknown = false;
            if (!s_warnedUnknown) {
                s_warnedUnknown = true;
                VL_WARN_MT(__FILE__, __LINE__, "randomize",
                           "Solver returned unknown (timed out or incomplete), so randomize() "
                           "may return 0; warned once");
            }
            return VlSolverStatus::UNKNOWN;
        }
        // Consume the whole error, so the next read starts on a reply boundary
        if (isSolverError(line)) finishErrorReply(is, line);
        warnSolverReply(line);
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

public:
    std::iostream& os() VL_REQUIRES(m_mutex) { return m_proc; }
    // The pipe may hold bytes of an abandoned reply, so replace the solver
    void abandon() VL_REQUIRES(m_mutex) { m_dirty = true; }

    // Read a check-sat status; once one fails, so does every later read
    VlSolverStatus readStatus() VL_REQUIRES(m_mutex) {
        // A status the runtime cannot use fails the call. It may be the error
        // reply to an earlier command of the batch, so the replies of the later
        // commands are still queued; they are skipped when the transaction ends.
        if (m_stale) return VlSolverStatus::FAIL;
        const VlSolverStatus status = ::readStatus(m_proc);
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

    // Start a transaction, spawning or respawning the solver as needed
    bool begin() VL_REQUIRES(m_mutex) {
        m_dirty = false;
        if (m_state == State::BROKEN) {
            if (m_consecFails >= MAX_CONSEC_FAILS) {
                m_state = State::DISABLED;
                VL_WARN_MT(__FILE__, __LINE__, "randomize",
                           "Solver failed repeatedly, so randomize() returns 0 from now on");
            } else if (!m_warnedRestart) {
                m_warnedRestart = true;
                VL_WARN_MT(__FILE__, __LINE__, "randomize",
                           "Solver died or replied unreadably, so this randomize() returned 0; "
                           "restarting it, warned once");
            }
        }
        if (m_state == State::UNSTARTED || m_state == State::BROKEN) spawn();
        return m_state == State::LIVE;
    }

    // End a transaction; a solver left out of step or dead is replaced next time
    void end() VL_REQUIRES(m_mutex) {
        bool healthy = !m_dirty && !m_proc.fail() && (!m_stale || resync());
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
            ++m_consecFails;
        }
        m_dirty = false;
        m_stale = false;
    }

private:
    // Skip queued replies up to an echoed marker; false if the solver went away
    bool resync() VL_REQUIRES(m_mutex) {
        m_proc << "(echo \"vl_resync\")\n";
        std::string line;
        // z3 prints the echoed string without quotes, the SMT-LIB 2.6 response with them; the
        // replies queued before it answer earlier commands, so cannot contain it
        while (readLine(m_proc, line) && line.find("vl_resync") == std::string::npos) {}
        return !m_proc.fail();
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
        m_proc << "(reset)\n";
        if (readStatus() == VlSolverStatus::SAT) {
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

static std::string readUntilBalanced(std::istream& stream) {
    std::string result;
    std::string token;
    int parenCount = 1;
    while (stream >> token) {
        for (const char c : token) {
            if (c == '(') {
                ++parenCount;
            } else if (c == ')') {
                --parenCount;
            }
        }
        result += token + " ";
        if (parenCount == 0) break;
    }
    return result;
}

static std::string parseNestedSelect(const std::string& nested_select_expr,
                                     std::vector<std::string>& indices) {
    std::istringstream nestedStream(nested_select_expr);
    std::string name;
    std::string idx;
    nestedStream >> name;
    if (name == "(select") {
        const std::string further_nested_expr = readUntilBalanced(nestedStream);
        name = parseNestedSelect(further_nested_expr, indices);
    }
    std::getline(nestedStream, idx, ')');
    indices.push_back(idx);
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
// True if val is "#b/#o/#x/#h" followed by digits legal for that base
static bool validSMTNum(const std::string& val) {
    size_t i = val.find('#');
    if (i == std::string::npos || ++i >= val.size()) return false;
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

// val must have passed validSMTNum
static void parseSMTNum(int obits, WDataOutP owp, const std::string& val) {
    size_t i = val.find('#') + 1;
    switch (val[i++]) {
    case 'b': _vl_vsss_based(owp, obits, 1, &val[i], 0, val.size() - i); break;
    case 'o': _vl_vsss_based(owp, obits, 3, &val[i], 0, val.size() - i); break;
    default: _vl_vsss_based(owp, obits, 4, &val[i], 0, val.size() - i); break;
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
    bool mayBeFrozen = m_randmodep || m_static_randmodep;
    // A disabled var means the class uses rand_mode, so it never shows up without one
    if (VL_UNCOVERABLE(!mayBeFrozen && !m_disabledVars.empty())) mayBeFrozen = true;
    if (!mayBeFrozen) return false;
    for (const auto& var : m_vars) {
        if (isFrozenVar(var.first, *var.second)) return true;
    }
    return false;
}

bool VlRandomizer::next_check_only(VlRNGReseeds& rngr) { return nextRandomize(rngr, true); }

bool VlRandomizer::next(VlRNGReseeds& rngr) { return nextRandomize(rngr, false); }

bool VlRandomizer::next_size(VlRNGReseeds& rngr) { return nextRandomize(rngr, false, true); }

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

// b is a sorted, disjoint membership domain. a may be the original overlapping
// dist buckets: retain each contribution so overlaps add their weights.
VlRandomizer::FastRanges VlRandomizer::fastIntersect(const FastRanges& a, const FastRanges& b) {
    FastRanges result;
    for (const FastRange& range : a) {
        auto it = std::lower_bound(b.begin(), b.end(), range.lo,
                                   [](const FastRange& r, QData lo) { return r.hi < lo; });
        for (; it != b.end() && it->lo <= range.hi; ++it) {
            result.push_back({std::max(range.lo, it->lo), std::min(range.hi, it->hi), range.weight,
                              range.divisor});
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
    const FastRanges ranges = distp ? fastIntersect(distp->ranges, domain) : domain;
    // Convert rational :/ per-value weights to exact integer masses. No floating
    // point rounding and no rejection from the original (possibly huge) domain.
    QData denominator = 1;
    for (const FastRange& range : ranges) {
        if (!range.divisor) return false;
        QData a = denominator;
        QData b = range.divisor;
        while (b) {
            const QData remainder = a % b;
            a = b;
            b = remainder;
        }
        const QData factor = range.divisor / a;
        if (factor > std::numeric_limits<QData>::max() / denominator) return false;
        denominator *= factor;
    }
    QData total = 0;
    std::vector<QData> masses;
    masses.reserve(ranges.size());
    for (const FastRange& range : ranges) {
        const QData scale = denominator / range.divisor;
        if (range.weight > std::numeric_limits<QData>::max() / scale) return false;
        const QData weight = range.weight * scale;
        const QData count = range.hi - range.lo + 1;
        if (!count) return false;  // The finite cardinality cannot be represented
        if (count > std::numeric_limits<QData>::max() / weight) return false;
        const QData mass = count * weight;
        if (mass > std::numeric_limits<QData>::max() - total) return false;
        total += mass;
        masses.push_back(mass);
    }
    if (!total) return false;
    QData pick = vl_fastBelow(rngr, total);
    for (size_t i = 0; i < ranges.size(); ++i) {
        if (pick < masses[i]) {
            // Consecutive equal-weight units map uniformly onto the legal values.
            valuer = ranges[i].lo + pick / (masses[i] / (ranges[i].hi - ranges[i].lo + 1));
            return true;
        }
        pick -= masses[i];
    }
    return false;  // Unreachable: the cumulative masses equal total
}

// A hard singleton view fixes exactly those physical bits. It does not
// consume probability mass or silently pin any bits outside that view.
bool VlRandomizer::fastPinned(const FastConstraint& constraint) {
    return !constraint.isSoft && !constraint.isDist && !constraint.isEnum
           && constraint.ranges.size() == 1
           && constraint.ranges[0].lo == constraint.ranges[0].hi;
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
        FastDomain& domain = domains[indices.at(constraint.datap)];
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
        FastDomain& domain = domains[indices.at(it->datap)];
        FastRanges intersection = fastIntersect(domain.ranges, fastUnion(it->ranges));
        if (intersection.empty()) continue;
        domain.ranges = std::move(intersection);
        if (it->isDist) {
            if (domain.distp) return -1;
            domain.distp = &*it;
        }
    }
    const size_t freeDomains = std::count_if(domains.begin(), domains.end(), [](const FastDomain& d) {
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
    if (m_ug2.rngReseeds != rngr.reseeds()) m_ug2 = Unigen2State{};

    // Fix the function arguments solved in earlier rounds (IEEE 1800-2023 18.5.11)
    for (const FuncArgRound& argRound : m_funcArgRounds) {
        if (argRound.round < m_funcRound && !argRound.pin.empty()) {
            m_constraints.push_back(argRound.pin);
            m_constraintVarEnds.push_back(m_constraintVarNames.size());  // Names no randc
        }
    }

    // Pinned vars make phase ordering moot; skip phased path in check-only.
    bool result;
    if (!m_checkOnly && !m_solveBefore.empty()) {
        result = nextPhased(rngr, sess, uniqueExprs);
    } else {
        result = nextFlat(rngr, sess, uniqueExprs);
    }
    m_ug2.rngReseeds = rngr.reseeds();
    m_checkOnly = false;
    m_sizeSolve = false;
    m_sizeSolved = sizeSolve && result;
    return result;
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

void VlRandomizer::emitDefines(std::ostream& os) const {
    os << "(define-fun __Vbv ((b Bool)) (_ BitVec 1) (ite b #b1 #b0))\n";
    os << "(define-fun __Vbool ((v (_ BitVec 1))) Bool (= #b1 v))\n";
}

void VlRandomizer::emitDeclares(std::ostream& os, bool pinCurrent) const {
    for (const auto& var : m_vars) {
        if (var.second->dimension() > 0) {
            auto arrVarsp = std::make_shared<const ArrayInfoMap>(m_arr_vars);
            var.second->setArrayInfo(arrVarsp);
        }
        os << "(declare-fun " << var.first << " () ";
        var.second->emitType(os);
        os << ")\n";
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
    for (int attempt = 0; attempt < (hasRandc ? 2 : 1); ++attempt) {
        os << "(set-option :produce-models true)\n";
        if (!solverSamples()) {
            // Lets the diversity pins learn which assumptions conflict.
            os << "(set-option :produce-unsat-assumptions true)\n";
        } else if (!m_checkOnly) {
            // Check-only results are not random, so leave the random state alone
            emitSolverSeed(os, rngr);
        }
        os << "(set-logic " << solverLogic() << ")\n";
        emitDefines(os);
        emitDeclares(os, m_checkOnly);
        emitAsserts(os, uniqueExprs, false);

        // randc exclusions vs. a pinned current value would make every check
        // trivially UNSAT after the first cycle.
        if (!m_checkOnly) emitRandcExclusions(os);

        relaxSoftConstraints(sess);
        os << "(check-sat)\n";
        const VlSolverStatus status = sess.readStatus();

        if (status != VlSolverStatus::SAT) {
            if (status != VlSolverStatus::UNSAT) return false;
            os << "(reset)\n";
            // If randc vars have used values, this may be cycle exhaustion - retry
            if (hasRandc && !m_randcUsedValues.empty() && attempt == 0) {
                m_randcUsedValues.clear();
                continue;  // Retry without exclusions
            }
            // Skip the unsat-core path in check-only: it re-declares vars
            // without pinning, so the solver's free assignment would clobber
            // user state.
            if (m_checkOnly) return false;
            // Genuine unsat: report via unsat-core
            reportUnsatSetup(sess, uniqueExprs);
            return false;
        }
        if (!applyModel(sess)) return false;

        if (!m_checkOnly) {
            if (!solverSamples()) solveDiversity(rngr, sess);
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

        // generateSamples() always finds a candidate in practice
        if (VL_UNCOVERABLE(!generateSamples(sess, rngr))) return false;
    }

    // Cached or just refilled - there is a witness to write into the variables
    Witness witness = std::move(m_ug2.loThreshWitnesses.back());
    m_ug2.loThreshWitnesses.pop_back();
    writeBackWitness(witness);
    return true;
}

void VlRandomizer::writeBackWitness(const Witness& witness) {
    for (const auto& varEntry : witness) {
        const auto& varp = m_vars.at(varEntry.first);
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
            std::string exprHead;
            is >> exprHead;  // bare var name, or literally "(select" if an array element
            const bool isSelect = exprHead == "(select";
            if (isSelect) readUntilBalanced(is);
            if (VL_UNLIKELY(!isSelect && exprHead != entry.first)) return -1;
            std::string value;
            std::getline(is, value, ')');
            // The batch outlives this call, so reject a bad value before it is cached
            if (VL_UNLIKELY(!validSMTNum(value))) return -1;
            witness[entry.first][entry.second] = value;
        }  // LCOV_EXCL_BR_LINE
        if (VL_UNLIKELY(!(is >> c) || c != ')')) return -1;  // LCOV_EXCL_BR_LINE

        // Forbid this exact assignment so the next
        // (check-sat) is forced to find a genuinely different witness.
        solver << "(assert (not (and";
        for (const auto& varEntry : witness) {
            for (const auto& elemEntry : varEntry.second) {
                solver << " (=";
                m_vars.at(varEntry.first)->emitElement(solver, elemEntry.first);
                solver << ' ' << elemEntry.second << ")";
            }
        }
        solver << ")))\n";
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
        // #b0 seeds the bvxor chain so it's always >=2 operands (valid even
        // if this equation's coin flips happen to select zero/one bits).
        // 0 xor 0 == 0, 0 xor 1 == 1, so the seed cannot change the result.
        solver << " (bvxor #b0";
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
    for (int t = 0; t < 3; ++t) {  // LCOV_EXCL_BR_LINE - Always finds a candidate in practice
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
    m_ug2.lastSuccessI = -1;  // LCOV_EXCL_LINE
    return false;  // LCOV_EXCL_LINE
}

void VlRandomizer::solveDiversity(VlRNG& rngr, VlSolverSession& sess,
                                  const std::set<std::string>* fixedp) VL_REQUIRES(sess.m_mutex) {
    // Tie each variable or array element to a random value via an assumption literal and
    // drop the literals that conflict with the constraints. Dropped terms that can still
    // change are split in halves that are tied again, down to single bits, so free bits
    // come out uniform and the surviving literals steer constrained ones (value < N,
    // #7563). A term that cannot (equal to another variable, or a solved size) costs a
    // check or two rather than one per bit, and wide data needs no per-bit literal or
    // XOR constraint. Variables in fixedp are already pinned, so skipped.
    // The solver checks are bounded. When several wide parts of an element conflict and
    // the first one cannot change while the others keep their values, the element is
    // left as it is: it is likely one of a few constants, which random parts never fit,
    // so splitting would cost a check per part down to single bits. Past
    // diversityMaxChecks checks the literals kept so far are the result.
    std::iostream& os = sess.os();
    const auto emitTerm = [&](const PinTerm& term) {
        const bool whole = term.width == term.varp->width();
        if (!whole) os << " ((_ extract " << term.lsb + term.width - 1 << ' ' << term.lsb << ')';
        term.varp->emitElement(os, term.elem);
        if (!whole) os << ')';
    };
    std::vector<PinTerm> terms;
    for (const auto& var : m_vars) {
        if (fixedp && fixedp->count(var.first)) continue;
        const int width = var.second->width();
        for (int j = 0; j < var.second->totalWidth() / width; ++j) {
            terms.push_back({var.second.get(), j, 0, width, static_cast<int>(terms.size())});
        }
    }
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
    while (!terms.empty() && checksLeft > 0) {
        for (size_t k = 0; k < terms.size(); ++k) {
            os << "(declare-fun __Va" << lits + k << " () Bool)\n";
            os << "(assert (= __Va" << lits + k << " (=";
            emitTerm(terms[k]);
            os << " #b";
            IData bits = 0;
            for (int b = 0; b < terms[k].width; ++b) {
                if (!(b & VL_SIZEBITS_I)) bits = VL_RANDOM_RNG_I(rngr);
                os << (VL_BITISSET_I(bits, b & VL_SIZEBITS_I) ? '1' : '0');
            }
            terms[k].value0 = VL_BITISSET_I(bits, (terms[k].width - 1) & VL_SIZEBITS_I) ? 1 : 0;
            os << ")))\n";
        }
        std::vector<int> slotIds;
        settled = assumeDropping(sess, keep, lits, terms, dropped, checksLeft, nullptr, &slotIds,
                                 &satisfiedLeft);
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
        if (!readValues(sess, values) || values.size() != conflicted.size()) return;
        for (size_t k = 0; k < conflicted.size(); ++k) {
            os << "(declare-fun __Va" << lits + k << " () Bool)\n";
            os << "(assert (= __Va" << lits + k << " (not (=";
            emitTerm(conflicted[k]);
            os << ' ' << values[k] << "))))\n";
        }
        std::vector<bool> guessed;
        settled = assumeDropping(sess, keep, lits, conflicted, dropped, checksLeft, &guessed);
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
            if (!settled && status != VlSolverStatus::UNSAT) break;
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
            if (settled) satisfied();
            if (status == VlSolverStatus::UNSAT) stopped.insert(it.first);
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
        // Out of checks, or the solver failed (and then likely fails this check too)
        os << "(check-sat-assuming (" << keep << "))\n";
        if (sess.readStatus() != VlSolverStatus::SAT) return;
    }
    applyModel(sess);
}

bool VlRandomizer::assumeDropping(VlSolverSession& sess, const std::string& keep, int first,
                                  const std::vector<PinTerm>& terms, std::vector<bool>& droppedr,
                                  int& checksLeftr, std::vector<bool>* guessedp,
                                  std::vector<int>* slotIdsp, int* satisfiedLeftp)
    VL_REQUIRES(sess.m_mutex) {
    std::iostream& os = sess.os();
    droppedr.assign(terms.size(), false);
    if (guessedp) guessedp->assign(terms.size(), false);
    if (slotIdsp) slotIdsp->assign(terms.size(), -1);
    int nslots = 0;
    // Conflicts per part of an array's elements (and pinned value, for a single bit), and
    // whether each of them was among others in its unsat core
    std::map<std::tuple<const VlRandomVar*, int, int, int>, std::pair<int, bool>> slotConflicts;
    while (checksLeftr-- > 0) {
        os << "(check-sat-assuming (" << keep;
        for (size_t k = 0; k < terms.size(); ++k) {
            if (!droppedr[k]) os << " __Va" << first + k;
        }
        os << "))\n";
        const VlSolverStatus status = sess.readStatus();
        if (status == VlSolverStatus::SAT) return true;
        // Unknown or failure: the solution already written stands
        if (status != VlSolverStatus::UNSAT) return false;
        // Drop the narrowest term of the core: wide data rarely causes the conflict.
        // The core only names active literals; ones before first are kept literals.
        // A core need not be minimal, so a pick among several is only a guess.
        int pick = -1;
        int candidates = 0;
        for (const int idx : readUnsatAssumptions(sess)) {
            const int k = idx - first;
            if (k < 0 || k >= static_cast<int>(terms.size()) || droppedr[k]) continue;
            ++candidates;
            if (pick < 0 || terms[k].width < terms[pick].width) pick = k;
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
        // all only if a few of the other elements cannot take their pin either.
        if (!slotIdsp) continue;
        const PinTerm& pickTerm = terms[pick];
        const auto slotOf = [](const PinTerm& term) {
            return std::make_tuple(term.varp, term.lsb, term.width,
                                   term.width == 1 ? term.value0 : 0);
        };
        std::pair<int, bool>& conflicts = slotConflicts[slotOf(pickTerm)];
        if (conflicts.first++ == 0) conflicts.second = true;
        conflicts.second &= candidates > 1;
        if (conflicts.first < diversitySlotConflicts) continue;
        std::vector<size_t> members;
        for (size_t k = 0; k < terms.size(); ++k) {
            if (!droppedr[k] && slotOf(terms[k]) == slotOf(pickTerm)) members.push_back(k);
        }
        bool othersFit = false;
        if (pickTerm.width == 1 && !conflicts.second) {
            for (size_t i = 0; i < std::min<size_t>(diversitySlotSamples, members.size()); ++i) {
                if (checksLeftr-- <= 0) return false;
                os << "(check-sat-assuming (" << keep << " __Va"
                   << first + members[diversitySample(i, members.size())] << "))\n";
                othersFit = sess.readStatus() == VlSolverStatus::SAT;
                if (!othersFit) continue;
                if (--*satisfiedLeftp <= 0) checksLeftr = 0;
                break;
            }
        }
        if (othersFit) {
            conflicts.first = 0;  // They go one by one
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

bool VlRandomizer::readValues(VlSolverSession& sess, std::vector<std::string>& valuesr)
    VL_REQUIRES(sess.m_mutex) {
    std::string reply;
    if (!sess.readSExpr(reply)) return false;
    if (isSolverError(reply)) {
        warnSolverReply(reply);
        return false;
    }
    // Each value is the last token directly inside its (term value) pair
    int depth = 0;
    std::string token;
    std::string last;
    for (const char c : reply) {
        if (c != '(' && c != ')' && !std::isspace(static_cast<unsigned char>(c))) {
            token += c;
            continue;
        }
        if (depth == 2 && !token.empty()) last = token;
        token.clear();
        if (c == '(') {
            if (++depth == 2) last.clear();
        } else if (c == ')' && depth-- == 2) {
            if (!validSMTNum(last)) return false;
            valuesr.push_back(last);
        }
    }
    return true;
}

// Re-add softs highest-priority first, dropping incompatible ones.
void VlRandomizer::relaxSoftConstraints(VlSolverSession& sess) VL_REQUIRES(sess.m_mutex) {
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
            if (status == VlSolverStatus::FAIL) return;
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
        warnSolverReply(reply);
        return {};
    }
    // The response lists only "__Va<N>" literals; collect each full integer run.
    return scanIntRuns(reply);
}

// Re-solve with named asserts so an unsat core can name the failing constraints
void VlRandomizer::reportUnsatSetup(VlSolverSession& sess,
                                    const std::vector<std::string>& uniqueExprs)
    VL_REQUIRES(sess.m_mutex) {
    std::iostream& os = sess.os();
    os << "(set-option :produce-unsat-cores true)\n";
    os << "(set-logic QF_ABV)\n";
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
        warnSolverReply(reply);
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
    size_t requested = 0;
    std::stringstream getValueStr;
    for (const auto& var : m_vars) {
        if (var.second->dimension() > 0) {
            auto arrVarsp = std::make_shared<const ArrayInfoMap>(m_arr_vars);
            var.second->setArrayInfo(arrVarsp);
            requested += var.second->countMatchingElements(m_arr_vars, var.second->name());
        } else {
            ++requested;
        }
        var.second->emitGetValue(getValueStr);
    }
    if (getValueStr.str() == "") {
        // Mark as m_checkOnly to skip generation of any subsequent solver calls
        m_checkOnly = true;
        return true;
    }
    os << "(get-value (" << getValueStr.str() << "))\n";
    std::string reply;
    if (!sess.readSExpr(reply)) return false;
    if (isSolverError(reply)) {
        warnSolverReply(reply);
        return false;
    }
    std::istringstream is{reply};
    return parseModel(is, requested);
}

bool VlRandomizer::parseModel(std::istream& is, size_t requested) {
    // Quasi-parse S-expression of the form ((x #xVALUE) (y #bVALUE) (z #xVALUE))
    char c = 0;
    is >> c;  // The '(' opening the readSExpr-balanced reply
    // Stage writes; commit only after the whole reply parses so failure keeps prior values
    std::vector<std::tuple<const VlRandomVar*, std::string, std::string>> staged;
    // Every requested term must come back exactly once, whether or not it is written
    std::set<std::string> answered;
    while (true) {
        if (VL_UNCOVERABLE(!(is >> c))) return false;  // Balanced reply breaks at ')' first
        if (c == ')') break;
        if (c != '(') {
            VL_WARN_MT(__FILE__, __LINE__, "randomize",
                       "Internal: Unable to parse solver's response: invalid S-expression");
            return false;
        }
        std::string name;
        std::string idx;
        std::string value;
        std::vector<std::string> indices;
        is >> name;
        indices.clear();
        if (name == "(select") {
            const std::string selectExpr = readUntilBalanced(is);
            name = parseNestedSelect(selectExpr, indices);
        }
        std::getline(is, value, ')');
        const auto it = m_vars.find(name);
        if (it == m_vars.end()) {
            VL_WARN_MT(__FILE__, __LINE__, "randomize",
                       "Internal: Unable to parse solver's response: unknown variable");
            return false;
        }
        const VlRandomVar& varr = *it->second;
        std::string key = name;
        for (const auto& index : indices) key += index;
        if (!answered.insert(key).second) {
            VL_WARN_MT(__FILE__, __LINE__, "randomize",
                       "Internal: Unable to parse solver's response: repeated variable");
            return false;
        }
        if (!varr.randModeIdxNone()) {
            // Static rand vars have their rand_mode in a class-package shared queue,
            // not the per-instance one.
            const VlQueue<CData>* const modep
                = m_staticVars.count(name) ? m_static_randmodep : m_randmodep;
            if (modep && !modep->at(varr.randModeIdx())) continue;
        }
        if (m_disabledVars.count(name)) continue;
        if (!indices.empty()) {
            std::ostringstream oss;
            oss << varr.name();
            for (const auto& hex_index : indices) {
                const size_t start = hex_index.find_first_not_of(" ");
                if (start == std::string::npos || hex_index.substr(start, 2) != "#x") {
                    VL_FATAL_MT(__FILE__, __LINE__, "randomize",
                                "hex_index contains invalid format");
                    continue;
                }
                std::string trimmed_hex = hex_index.substr(start + 2);
                if (!validSMTNum(hex_index)) {
                    VL_WARN_MT(__FILE__, __LINE__, "randomize",
                               "Internal: Unable to parse solver's response: invalid array index");
                    return false;
                }

                if (trimmed_hex.size() <= 8) {  // Small numbers: <= 32 bits
                    // Convert to decimal and output directly
                    oss << "[" << std::to_string(std::stoll(trimmed_hex, nullptr, 16)) << "]";
                } else {  // Large numbers: > 32 bits
                    // Trim leading zeros and handle empty case
                    trimmed_hex.erase(0, trimmed_hex.find_first_not_of('0'));
                    oss << "[" << (trimmed_hex.empty() ? "0" : trimmed_hex) << "]";
                }
            }
            const std::string indexed_name = oss.str();

            const auto iti = std::find_if(m_arr_vars.begin(), m_arr_vars.end(),
                                          [&indexed_name](const auto& entry) {
                                              return entry.second->m_name == indexed_name;
                                          });
            if (iti != m_arr_vars.end()) {
                std::ostringstream ss;
                ss << "#x" << std::hex << std::setw(8) << std::setfill('0')
                   << iti->second->m_index;
                idx = ss.str();
            } else {
                VL_FATAL_MT(__FILE__, __LINE__, "randomize",
                            "indexed_name not found in m_arr_vars");
            }
        }
        // Reject before any commit, so a bad value later in the reply cannot
        // leave earlier ones written
        if (!validSMTNum(value)) {
            VL_WARN_MT(__FILE__, __LINE__, "randomize",
                       "Internal: Unable to parse solver's response: invalid value");
            return false;
        }
        staged.emplace_back(&varr, idx, value);
    }
    if (answered.size() != requested) {
        VL_WARN_MT(__FILE__, __LINE__, "randomize",
                   "Internal: Unable to parse solver's response: incomplete model");
        return false;
    }
    for (const auto& entry : staged)
        std::get<0>(entry)->set(std::get<1>(entry), std::get<2>(entry));
    return true;
}

void VlRandomizer::hard(std::string constraint, std::initializer_list<const char*> varNames,
                        const char* filename, uint32_t linenum, const char* source) {
    m_constraints.emplace_back(std::move(constraint));
    // Stored for every constraint: a randomize() with clause registers its constraints
    // before markRandc() marks its randc variables, so whether the names are needed isn't
    // known yet here
    m_constraintVarNames.insert(m_constraintVarNames.end(), varNames.begin(), varNames.end());
    m_constraintVarEnds.push_back(m_constraintVarNames.size());
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
                        const char* /*filename*/, uint32_t /*linenum*/, const char* /*source*/) {
    m_softConstraints.emplace_back(std::move(constraint));
    m_softVarNames.insert(m_softVarNames.end(), varNames.begin(), varNames.end());
    m_softVarEnds.push_back(m_softVarNames.size());
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

void VlRandomizer::clearConstraints() {
    m_fastConstraints.clear();
    m_fastDisabled = false;
    m_constraints.clear();
    m_constraintVarNames.clear();
    m_constraintVarEnds.clear();
    m_constraints_line.clear();
    m_solveBefore.clear();
    m_softConstraints.clear();
    m_softVarNames.clear();
    m_softVarEnds.clear();
    m_uniqueArrays.clear();  // Re-registered by constraint setup
    m_frozenPins.clear();  // Likewise re-added
    // Keep m_vars for class member randomization
}

void VlRandomizer::clearAll() {
    m_fastConstraints.clear();
    m_fastDisabled = false;
    m_constraints.clear();
    m_constraintVarNames.clear();
    m_constraintVarEnds.clear();
    m_softConstraints.clear();
    m_softVarNames.clear();
    m_softVarEnds.clear();
    m_vars.clear();
    m_enumDomains.clear();
    m_randcVarNames.clear();
    m_randcUsedValues.clear();
    m_randcConstraintHash = 0;
}

void VlRandomizer::clear_elem_vars(const std::string& arrayName) {
    // Registered as "<arrayName>.<index>.<field>", and again for the objects the array holds
    // at each randomize(), so objects that were removed or replaced are not referenced
    const std::string prefix = arrayName + ".";
    auto it = m_vars.lower_bound(prefix);
    while (it != m_vars.end() && it->first.compare(0, prefix.size(), prefix) == 0) {
        it = m_vars.erase(it);
    }
}

void VlRandomizer::markRandc(const std::string& name) { m_randcVarNames.insert(name); }

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

const char* VlRandomizer::solverLogic() const {
    // Without arrays, QF_BV lets z3 answer the incremental checks of the sampling with
    // its bit-blasting SAT solver, which is several times faster than the SMT core it
    // uses for QF_ABV. Phased solves keep phasedLogic(): their XOR rounds solve slower
    // with QF_BV.
    for (const auto& var : m_vars) {
        if (var.second->dimension() > 0) return "QF_ABV";
    }
    // A constraint may hold an array term of its own, such as an array literal
    for (const auto* const constraintsp : {&m_constraints, &m_softConstraints}) {
        for (const std::string& constraint : *constraintsp) {
            if (constraint.find("(Array ") != std::string::npos) return "QF_ABV";
        }
    }
    return "QF_BV";
}

const char* VlRandomizer::phasedLogic() const {
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

    for (size_t phase = 0; phase < layers.size(); phase++) {
        const bool isFinalPhase = (phase == layers.size() - 1);

        os << "(set-option :produce-models true)\n";
        if (solverSamples()) {
            emitSolverSeed(os, rngr);
        } else if (isFinalPhase) {
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

        // Soft constraints participate in every phase, priority-ordered.
        relaxSoftConstraints(sess);

        // Initial check-sat WITHOUT diversity (guaranteed sat if constraints are consistent)
        os << "(check-sat)\n";
        const VlSolverStatus status = sess.readStatus();
        if (status != VlSolverStatus::SAT) {
            // Only exhausted randc values are worth a retry; a lost solver is not
            if (status == VlSolverStatus::UNSAT) exhaustedr = !m_randcUsedValues.empty();
            return false;
        }

        if (isFinalPhase) {
            if (!applyModel(sess)) return false;
            if (!solverSamples()) {
                std::set<std::string> fixed;  // Variables of the earlier layers
                for (size_t i = 0; i < phase; ++i)
                    fixed.insert(layers[i].begin(), layers[i].end());
                solveDiversity(rngr, sess, &fixed);
            }
            // Record solved randc values for future exclusion
            recordRandcValues();
        } else {
            if (!solvePhaseValues(sess, rngr, layers[phase], solvedValues)) return false;
            os << "(reset)\n";
        }
    }

    return true;
}

// Intermediate phase: extract this layer's values, then optionally try one diversity round
bool VlRandomizer::solvePhaseValues(VlSolverSession& sess, VlRNG& rngr,
                                    const std::vector<std::string>& layerVars,
                                    std::map<std::string, std::string>& solvedValuesr)
    VL_REQUIRES(sess.m_mutex) {
    std::iostream& os = sess.os();
    const auto emitGetValueCmd = [&]() {
        os << "(get-value (";
        for (const auto& varName : layerVars) {
            const VlRandomVar* const varp = solveBeforeVarp(varName);
            if (varp->dimension() > 0) {
                auto arrVarsp = std::make_shared<const ArrayInfoMap>(m_arr_vars);
                varp->setArrayInfo(arrVarsp);
                // Enumerable arrays: query each element for a QF_ABV-safe pin.
                if (varp->hasMatchingElements(m_arr_vars, varp->name())) {
                    varp->emitGetValue(os);
                    continue;
                }
            }
            os << varp->name() << " ";
        }
        os << "))\n";
    };
    // Get baseline values (deterministic, always valid)
    emitGetValueCmd();
    if (!readPhaseValues(sess, solvedValuesr)) return false;
    if (solverSamples()) return true;

    // Try diversity: add random constraint, re-check. If sat, get
    // updated (more diverse) values. If unsat, keep baseline values.
    // Scoped to this layer's own vars -- see randomConstraint's comment.
    os << "(assert ";
    randomConstraint(os, rngr, _VL_SOLVER_HASH_LEN, &layerVars);
    os << ")\n";
    os << "(check-sat)\n";
    if (sess.readStatus() == VlSolverStatus::SAT) {
        emitGetValueCmd();
        (void)readPhaseValues(sess, solvedValuesr);
    }
    return true;
}

bool VlRandomizer::readPhaseValues(VlSolverSession& sess,
                                   std::map<std::string, std::string>& solvedValuesr)
    VL_REQUIRES(sess.m_mutex) {
    std::string reply;
    if (!sess.readSExpr(reply)) return false;
    if (isSolverError(reply)) {
        warnSolverReply(reply);
        return false;
    }
    std::istringstream is{reply};
    return parsePhaseValues(is, solvedValuesr);
}

bool VlRandomizer::parsePhaseValues(std::istream& is,
                                    std::map<std::string, std::string>& solvedValuesr) {
    // Parse ((name value) ...): one paren-depth counter drives every match.
    char c = 0;
    is >> c;  // outer '('
    if (c != '(') return false;
    int depth = 1;
    std::string tokens[2];
    std::string cur;
    int fields = 0;
    const auto flush = [&]() {
        if (cur.empty()) return;
        if (fields < 2) tokens[fields] = cur;
        ++fields;
        cur.clear();
    };
    while (depth > 0 && is.get(c)) {
        if (c == '(') {
            ++depth;
            if (depth >= 3) cur += c;
        } else if (c == ')') {
            --depth;
            if (depth >= 2) {
                cur += c;
            } else if (depth == 1) {
                flush();
                if (fields == 2) solvedValuesr[tokens[0]] = tokens[1];
                fields = 0;
            }
        } else if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
            if (depth >= 3) {
                cur += c;
            } else {
                flush();
            }
        } else {
            cur += c;
        }
    }
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
